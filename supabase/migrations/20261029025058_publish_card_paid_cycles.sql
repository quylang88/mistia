-- Row locks cannot fence a genuinely absent linked ledger ID. Serialize new
-- global ledger identities (including an ID-changing legacy UPDATE) with the
-- metadata RPC. Legacy financial writers share this identity lock with each
-- other; only the compared card RPC takes it exclusively. Their existing
-- conditional INSERT/UPDATE arbitration therefore stays in force.
create or replace function public.serialize_card_payment_ledger_identity()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public
as $$
declare keys bigint[]:='{}'; k bigint;
begin
    if tg_op='UPDATE' then keys:=array_append(keys,hashtextextended('card-payment-ledger:'||old.id::text,0)); end if;
    keys:=array_append(keys,hashtextextended('card-payment-ledger:'||new.id::text,0));
    for k in select distinct x from unnest(keys) x order by x loop perform pg_advisory_xact_lock_shared(k); end loop;
    return new;
end;
$$;
revoke all on function public.serialize_card_payment_ledger_identity() from public,anon,authenticated,service_role;
drop trigger if exists ledger_transactions_serialize_card_payment_identity on public.ledger_transactions;
create trigger ledger_transactions_serialize_card_payment_identity before insert or update of id
on public.ledger_transactions for each row execute function public.serialize_card_payment_ledger_identity();

-- An absent historical card/source wallet needs the same identity fence. Shared
-- birth/ID-edit locks preserve generic wallet writers' existing arbitration.
create or replace function public.serialize_card_payment_wallet_identity()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public
as $$
declare keys bigint[]:='{}'; k bigint;
begin
    if tg_op='UPDATE' then keys:=array_append(keys,hashtextextended('card-payment-wallet:'||old.id::text,0)); end if;
    keys:=array_append(keys,hashtextextended('card-payment-wallet:'||new.id::text,0));
    for k in select distinct x from unnest(keys) x order by x loop perform pg_advisory_xact_lock_shared(k); end loop;
    return new;
end;
$$;
revoke all on function public.serialize_card_payment_wallet_identity() from public,anon,authenticated,service_role;
drop trigger if exists ledger_wallets_serialize_card_payment_identity on public.ledger_wallets;
create trigger ledger_wallets_serialize_card_payment_identity before insert or update of id
on public.ledger_wallets for each row execute function public.serialize_card_payment_wallet_identity();

-- All-month card membership also covers legacy due-month markers. No RLS change.
create or replace function public.serialize_card_cycle_membership()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public
as $$
declare keys bigint[]:='{}'; k bigint;
begin
    if tg_op<>'INSERT' then
        if old.source_kind_raw_value='creditCard' then keys:=array_append(keys,hashtextextended('card-cycle:'||old.user_id::text||':'||old.source_id::text,0)); end if;
    end if;
    if tg_op<>'DELETE' then
        if new.source_kind_raw_value='creditCard' then keys:=array_append(keys,hashtextextended('card-cycle:'||new.user_id::text||':'||new.source_id::text,0)); end if;
    end if;
    for k in select distinct x from unnest(keys) x order by x loop perform pg_advisory_xact_lock(k); end loop;
    if tg_op='DELETE' then return old; end if;
    return new;
end;
$$;
revoke all on function public.serialize_card_cycle_membership() from public,anon,authenticated,service_role;
drop trigger if exists due_occurrence_records_serialize_card_membership on public.due_occurrence_records;
create trigger due_occurrence_records_serialize_card_membership before insert or update or delete
on public.due_occurrence_records for each row execute function public.serialize_card_cycle_membership();

-- Metadata only. Definer visibility is needed to distinguish an RLS-hidden
-- foreign ledger/wallet from genuine absence during tombstone publication.
-- Actor ownership is explicit for the target and every actual dependency;
-- no ledger, wallet, posting, charge, profile or RLS writes occur here.
create or replace function public.mutate_card_paid_cycle(
    p_cycle jsonb,p_expected_version bigint,p_expected_presence boolean,
    p_expected_ledger jsonb,p_expected_wallets jsonb,p_expected_cycles jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
    actor uuid:=auth.uid(); c public.due_occurrence_records%rowtype;
    old_c public.due_occurrence_records%rowtype; prior public.due_occurrence_records%rowtype;
    saved public.due_occurrence_records%rowtype;
    el public.ledger_transactions%rowtype; actual_l public.ledger_transactions%rowtype;
    payment public.ledger_transactions%rowtype; predecessor public.ledger_transactions%rowtype;
    ew public.ledger_wallets%rowtype; actual_w public.ledger_wallets%rowtype;
    source_w public.ledger_wallets%rowtype; card_w public.ledger_wallets%rowtype;
    item jsonb; typed jsonb; pair record; wanted uuid; allowed_links uuid[];
    expected_members jsonb; current_members jsonb; deleting boolean; same_financial boolean;
    currency text; identity_lock bigint;
begin
    if actor is null then raise exception 'card_payment_authentication_required'; end if;
    if jsonb_typeof(p_cycle) is distinct from 'object'
       or jsonb_typeof(p_expected_ledger) is distinct from 'object'
       or jsonb_typeof(p_expected_wallets) is distinct from 'object'
       or jsonb_typeof(p_expected_cycles) is distinct from 'array'
       or p_expected_version is null or p_expected_version not between 0 and 9223372036854775806
       or p_expected_presence is null or (not p_expected_presence and p_expected_version<>0)
       or jsonb_array_length(p_expected_cycles)>10000
       or (select count(*) from jsonb_object_keys(p_expected_ledger))>10001
       or (select count(*) from jsonb_object_keys(p_expected_wallets))>2
       or octet_length(p_expected_cycles::text)>1048576 or octet_length(p_expected_ledger::text)>4194304
       or octet_length(p_expected_wallets::text)>32768 or octet_length(p_cycle::text)>32768 then
        raise exception 'card_payment_invalid_group';
    end if;
    c:=jsonb_populate_record(null::public.due_occurrence_records,p_cycle);
    if exists(select 1 from jsonb_each(p_cycle) f where not(to_jsonb(c)?f.key)
       or jsonb_typeof(f.value) is distinct from jsonb_typeof(to_jsonb(c)->f.key))
       or (select array_agg(key order by key) from jsonb_object_keys(p_cycle) key) is distinct from
          (select array_agg(key order by key) from jsonb_object_keys(to_jsonb(c)) key)
       or c.id is null or c.user_id is null or c.source_id is null or c.linked_transaction_id is null
       or c.source_kind_raw_value is distinct from 'creditCard' or c.status_raw_value is distinct from 'paid'
       or c.amount_minor_snapshot is null or c.amount_minor_snapshot<=0 or c.last_modified_by_device_id is null
       or c.created_at is null or c.updated_at is null or c.scheduled_date is null or c.paid_at is null
       or not isfinite(c.created_at) or not isfinite(c.updated_at) or not isfinite(c.scheduled_date) or not isfinite(c.paid_at)
       or (c.deleted_at is not null and not isfinite(c.deleted_at))
       or c.selected_month_key is null or c.selected_month_key !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
       or c.sync_version is distinct from p_expected_version+1
       or jsonb_typeof(p_cycle->'amount_minor_snapshot') is distinct from 'number'
       or (p_cycle->>'amount_minor_snapshot') !~ '^[0-9]+$'
       or jsonb_typeof(p_cycle->'sync_version') is distinct from 'number' or (p_cycle->>'sync_version') !~ '^[0-9]+$'
       or p_cycle->>'id' is distinct from c.id::text or p_cycle->>'user_id' is distinct from c.user_id::text
       or p_cycle->>'source_id' is distinct from c.source_id::text or p_cycle->>'linked_transaction_id' is distinct from c.linked_transaction_id::text
       or p_cycle->>'last_modified_by_device_id' is distinct from c.last_modified_by_device_id::text then
        raise exception 'card_payment_invalid_group';
    end if;
    if actor<>c.user_id then raise exception 'card_payment_owner_required'; end if;
    deleting:=c.deleted_at is not null;
    if (select count(distinct value->>'id') from jsonb_array_elements(p_expected_cycles))<>jsonb_array_length(p_expected_cycles) then
        raise exception 'card_payment_invalid_group';
    end if;
    for item in select value from jsonb_array_elements(p_expected_cycles) loop
        if jsonb_typeof(item)<>'object' then raise exception 'card_payment_invalid_group'; end if;
        prior:=jsonb_populate_record(null::public.due_occurrence_records,item); typed:=to_jsonb(prior);
        if prior.id is null or prior.user_id is distinct from c.user_id or prior.source_kind_raw_value is distinct from 'creditCard'
           or prior.source_id is distinct from c.source_id
           or exists(select 1 from jsonb_each(item) f where not(typed?f.key) or jsonb_typeof(f.value) is distinct from jsonb_typeof(typed->f.key))
           or (select array_agg(key order by key) from jsonb_object_keys(item) key) is distinct from
              (select array_agg(key order by key) from jsonb_object_keys(typed) key) then
            raise exception 'card_payment_invalid_group';
        end if;
    end loop;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into expected_members
        from jsonb_populate_recordset(null::public.due_occurrence_records,p_expected_cycles) x;
    select array_agg(distinct id) into allowed_links from (
        select c.linked_transaction_id as id union all
        select x.linked_transaction_id from jsonb_populate_recordset(null::public.due_occurrence_records,p_expected_cycles) x
        where x.id=c.id or x.selected_month_key=c.selected_month_key or x.scheduled_date=c.scheduled_date or x.linked_transaction_id=c.linked_transaction_id
    ) links where id is not null;
    if not(p_expected_ledger?c.linked_transaction_id::text) then raise exception 'card_payment_invalid_group'; end if;
    for pair in select * from jsonb_each(p_expected_ledger) loop
        wanted:=pair.key::uuid;
        if pair.key<>wanted::text or not(wanted=any(allowed_links)) then raise exception 'card_payment_invalid_group'; end if;
        if pair.value<>'null'::jsonb then
            if jsonb_typeof(pair.value)<>'object' then raise exception 'card_payment_invalid_group'; end if;
            el:=jsonb_populate_record(null::public.ledger_transactions,pair.value); typed:=to_jsonb(el);
            if el.id is distinct from wanted or el.user_id is distinct from c.user_id
               or exists(select 1 from jsonb_each(pair.value) f where not(typed?f.key) or jsonb_typeof(f.value) is distinct from jsonb_typeof(typed->f.key)) then
                raise exception 'card_payment_invalid_group';
            end if;
        end if;
    end loop;
    for pair in select * from jsonb_each(p_expected_wallets) loop
        wanted:=pair.key::uuid;
        if pair.key<>wanted::text then raise exception 'card_payment_invalid_group'; end if;
        if pair.value<>'null'::jsonb then
            if jsonb_typeof(pair.value)<>'object' then raise exception 'card_payment_invalid_group'; end if;
            ew:=jsonb_populate_record(null::public.ledger_wallets,pair.value);typed:=to_jsonb(ew);
            if ew.id is distinct from wanted or ew.user_id is distinct from c.user_id
               or exists(select 1 from jsonb_each(pair.value) f where not(typed?f.key) or jsonb_typeof(f.value) is distinct from jsonb_typeof(typed->f.key)) then
                raise exception 'card_payment_invalid_group';
            end if;
        end if;
    end loop;
    -- Compatible with ordinary financial publication and balance-trigger order.
    perform pg_advisory_xact_lock(hashtextextended(c.user_id::text||':investment-cash',0));
    for identity_lock in select distinct hashtextextended('card-payment-ledger:'||key,0) from jsonb_object_keys(p_expected_ledger) key order by 1 loop
        perform pg_advisory_xact_lock(identity_lock);
    end loop;
    perform 1 from public.ledger_transactions where id in (select key::uuid from jsonb_object_keys(p_expected_ledger) key) order by id for update;
    for pair in select * from jsonb_each(p_expected_ledger) loop
        select * into actual_l from public.ledger_transactions where id=pair.key::uuid;
        if actual_l.id is not null then
            if pair.value='null'::jsonb or actual_l.user_id<>c.user_id then raise exception 'card_payment_ledger_changed'; end if;
            el:=jsonb_populate_record(null::public.ledger_transactions,pair.value);
            if to_jsonb(el) is distinct from to_jsonb(actual_l) then
                raise exception 'card_payment_ledger_changed';
            end if;
        elsif pair.value<>'null'::jsonb then raise exception 'card_payment_ledger_changed';
        end if;
        if pair.key=c.linked_transaction_id::text then payment:=actual_l; end if;
    end loop;
    for identity_lock in select distinct hashtextextended('card-payment-wallet:'||id::text,0)
        from (select c.source_id as id union select payment.source_wallet_id
              union select key::uuid from jsonb_object_keys(p_expected_wallets) key) identities
        where id is not null order by 1 loop
        perform pg_advisory_xact_lock(identity_lock);
    end loop;
    perform 1 from public.ledger_wallets where id=c.source_id or id=payment.source_wallet_id
        or id in (select key::uuid from jsonb_object_keys(p_expected_wallets) key) order by id for update;
    if exists(select 1 from public.ledger_wallets where (id=c.source_id or id=payment.source_wallet_id) and user_id<>c.user_id) then
        raise exception 'card_payment_wallet_changed';
    end if;
    for pair in select * from jsonb_each(p_expected_wallets) loop
        select * into actual_w from public.ledger_wallets where id=pair.key::uuid;
        if actual_w.id is not null then
            if pair.value='null'::jsonb or actual_w.user_id<>c.user_id then raise exception 'card_payment_wallet_changed'; end if;
            ew:=jsonb_populate_record(null::public.ledger_wallets,pair.value);
            if ew.id is distinct from actual_w.id or ew.user_id is distinct from actual_w.user_id
               or ew.created_at is distinct from actual_w.created_at or ew.sync_version is distinct from actual_w.sync_version
               or ew.kind_raw_value is distinct from actual_w.kind_raw_value or ew.currency_code is distinct from actual_w.currency_code
               or ew.deleted_at is distinct from actual_w.deleted_at or ew.is_archived is distinct from actual_w.is_archived
               or ew.archived_at is distinct from actual_w.archived_at or ew.system_purpose_raw_value is distinct from actual_w.system_purpose_raw_value then
                raise exception 'card_payment_wallet_changed';
            end if;
        elsif pair.value<>'null'::jsonb then raise exception 'card_payment_wallet_changed';
        end if;
    end loop;
    if not deleting then
        select * into source_w from public.ledger_wallets where id=payment.source_wallet_id;
        select * into card_w from public.ledger_wallets where id=c.source_id;
        currency:=upper(btrim(payment.source_currency_code));
        if payment.id is null or payment.user_id<>c.user_id or payment.deleted_at is not null or payment.is_archived
           or payment.primary_kind_raw_value is distinct from 'transfer' or payment.transfer_subtype_raw_value is distinct from 'internalTransfer'
           or payment.entry_status_raw_value is distinct from 'posted' or payment.debt_intent_raw_value is not null
           or payment.settlement_group_id is not null or payment.settlement_obligation_id is not null or payment.settlement_role_raw_value is not null
           or payment.reporting_expense_minor is not null or payment.reporting_income_minor is not null
           or payment.amount_minor<=0 or payment.amount_minor<c.amount_minor_snapshot or payment.occurred_at<>c.paid_at
           or coalesce(payment.destination_amount_minor,payment.amount_minor)<>payment.amount_minor
           or payment.destination_wallet_id is distinct from c.source_id or payment.source_wallet_id is null or payment.source_wallet_id=c.source_id
           or source_w.id is null or source_w.user_id<>c.user_id or source_w.deleted_at is not null
           or source_w.kind_raw_value not in ('cash','payPay','bank','eWallet','prepaid','crypto','other') or source_w.system_purpose_raw_value is not null
           or card_w.id is null or card_w.user_id<>c.user_id or card_w.deleted_at is not null
           or card_w.kind_raw_value is distinct from 'creditCard' or card_w.system_purpose_raw_value is not null
           or currency is null or currency !~ '^[A-Z]{3}$' or upper(btrim(source_w.currency_code)) is distinct from currency
           or upper(btrim(card_w.currency_code)) is distinct from currency
           or upper(btrim(coalesce(payment.destination_currency_code,payment.source_currency_code))) is distinct from currency
           or not(p_expected_wallets?source_w.id::text) or not(p_expected_wallets?card_w.id::text)
           or exists(select 1 from jsonb_object_keys(p_expected_wallets) key where key not in (source_w.id::text,card_w.id::text)) then
            raise exception 'card_payment_invalid_financial_footprint';
        end if;
    elsif payment.id is not null and payment.deleted_at is null then raise exception 'card_payment_ledger_changed';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('card-cycle:'||c.user_id::text||':'||c.source_id::text,0));
    select * into old_c from public.due_occurrence_records where id=c.id for update;
    if (old_c.id is not null) is distinct from p_expected_presence
       or (old_c.id is not null and (old_c.user_id<>c.user_id or old_c.sync_version<>p_expected_version)) then
        raise exception 'card_payment_version_conflict';
    end if;
    if old_c.id is not null and (old_c.created_at is distinct from c.created_at or old_c.source_kind_raw_value is distinct from 'creditCard'
       or old_c.source_id is distinct from c.source_id or (old_c.selected_month_key<>c.selected_month_key and old_c.scheduled_date<>c.scheduled_date)) then
        raise exception 'card_payment_invalid_identity';
    end if;
    perform 1 from public.due_occurrence_records where user_id=c.user_id and source_kind_raw_value='creditCard' and source_id=c.source_id order by id for update;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into current_members from public.due_occurrence_records x
        where x.user_id=c.user_id and x.source_kind_raw_value='creditCard' and x.source_id=c.source_id;
    if current_members<>expected_members then raise exception 'card_payment_membership_changed'; end if;
    for prior in select * from public.due_occurrence_records x where x.user_id=c.user_id and x.source_kind_raw_value='creditCard' and x.source_id=c.source_id
        and (x.id=c.id or x.selected_month_key=c.selected_month_key or x.scheduled_date=c.scheduled_date or x.linked_transaction_id=c.linked_transaction_id)
    loop
        if prior.id<>c.id then
            if deleting then continue; end if;
            if prior.deleted_at is null then raise exception 'card_payment_financial_sibling_conflict'; end if;
            if prior.status_raw_value in ('pending','skipped') and prior.paid_at is null and prior.linked_transaction_id is null then continue; end if;
        else
            same_financial:=(to_jsonb(prior)-array['sync_version','updated_at','last_modified_by_device_id','deleted_at'])=
                (to_jsonb(c)-array['sync_version','updated_at','last_modified_by_device_id','deleted_at']);
            if same_financial and prior.status_raw_value='paid' then
                if not deleting and prior.deleted_at is not null then raise exception 'card_payment_invalid_transition'; end if;
                continue;
            end if;
            if not deleting and prior.deleted_at is null and prior.status_raw_value in ('pending','skipped') and prior.paid_at is null and prior.linked_transaction_id is null then continue; end if;
            if deleting then raise exception 'card_payment_invalid_transition'; end if;
        end if;
        if prior.status_raw_value is distinct from 'paid' or prior.paid_at is null or prior.linked_transaction_id is null
           or c.paid_at<=prior.paid_at or (prior.deleted_at is not null and c.paid_at<=prior.deleted_at) then
            raise exception 'card_payment_invalid_transition';
        end if;
        if prior.linked_transaction_id<>c.linked_transaction_id then
            if not(p_expected_ledger?prior.linked_transaction_id::text) then raise exception 'card_payment_invalid_group'; end if;
            select * into predecessor from public.ledger_transactions where id=prior.linked_transaction_id;
            if predecessor.id is not null and (predecessor.user_id<>c.user_id or predecessor.deleted_at is null or c.paid_at<=predecessor.deleted_at
               or predecessor.occurred_at is distinct from prior.paid_at or predecessor.destination_wallet_id is distinct from c.source_id
               or predecessor.primary_kind_raw_value is distinct from 'transfer' or predecessor.transfer_subtype_raw_value is distinct from 'internalTransfer'
               or predecessor.entry_status_raw_value is distinct from 'posted'
               or predecessor.amount_minor<=0 or predecessor.amount_minor<prior.amount_minor_snapshot
               or predecessor.debt_intent_raw_value is not null or predecessor.settlement_group_id is not null
               or predecessor.settlement_obligation_id is not null or predecessor.settlement_role_raw_value is not null
               or predecessor.reporting_expense_minor is not null or predecessor.reporting_income_minor is not null
               or coalesce(predecessor.destination_amount_minor,predecessor.amount_minor)<>predecessor.amount_minor) then
                raise exception 'card_payment_invalid_transition';
            end if;
        end if;
    end loop;
    begin
        insert into public.due_occurrence_records as target
            (id,user_id,source_kind_raw_value,source_id,selected_month_key,scheduled_date,amount_minor_snapshot,status_raw_value,paid_at,linked_transaction_id,created_at,updated_at,deleted_at,sync_version,last_modified_by_device_id)
        values(c.id,c.user_id,c.source_kind_raw_value,c.source_id,c.selected_month_key,c.scheduled_date,c.amount_minor_snapshot,c.status_raw_value,c.paid_at,c.linked_transaction_id,c.created_at,c.updated_at,c.deleted_at,c.sync_version,c.last_modified_by_device_id)
        on conflict(id) do update set selected_month_key=excluded.selected_month_key,scheduled_date=excluded.scheduled_date,amount_minor_snapshot=excluded.amount_minor_snapshot,
            status_raw_value=excluded.status_raw_value,paid_at=excluded.paid_at,linked_transaction_id=excluded.linked_transaction_id,updated_at=excluded.updated_at,
            deleted_at=excluded.deleted_at,sync_version=excluded.sync_version,last_modified_by_device_id=excluded.last_modified_by_device_id
        where p_expected_presence and target.user_id=c.user_id and target.sync_version=p_expected_version and target.created_at=c.created_at
            and target.source_kind_raw_value='creditCard' and target.source_id=c.source_id
        returning * into saved;
    exception when unique_violation or insufficient_privilege then raise exception 'card_payment_version_conflict';
    end;
    if saved.id is null then raise exception 'card_payment_version_conflict'; end if;
    return to_jsonb(saved);
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise exception 'card_payment_invalid_group';
end;
$$;
revoke all on function public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb) from public,anon,service_role;
grant execute on function public.mutate_card_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb) to authenticated;
