-- Serialize installment month membership across both legacy row writers and the
-- compared RPC. No RLS policy, financial row, or legacy payload is changed.
create or replace function public.serialize_installment_cycle_membership()
returns trigger language plpgsql set search_path=pg_catalog,public
as $$
declare keys bigint[] := '{}'; k bigint;
begin
    if tg_op <> 'INSERT' then
        if old.source_kind_raw_value='installment' then
            keys:=array_append(keys,hashtextextended('installment-cycle:'||old.user_id::text||':'||old.source_id::text||':'||old.selected_month_key,0));
        end if;
    end if;
    if tg_op <> 'DELETE' then
        if new.source_kind_raw_value='installment' then
            keys:=array_append(keys,hashtextextended('installment-cycle:'||new.user_id::text||':'||new.source_id::text||':'||new.selected_month_key,0));
        end if;
    end if;
    for k in select distinct x from unnest(keys) x order by x loop perform pg_advisory_xact_lock(k); end loop;
    if tg_op='DELETE' then return old; end if;
    return new;
end;
$$;
revoke all on function public.serialize_installment_cycle_membership() from public, anon, authenticated, service_role;
drop trigger if exists due_occurrence_records_serialize_installment_membership on public.due_occurrence_records;
create trigger due_occurrence_records_serialize_installment_membership
before insert or update or delete on public.due_occurrence_records
for each row execute function public.serialize_installment_cycle_membership();

-- A paid marker is metadata about already-compared money. This function never
-- creates, edits, or reprices a ledger, wallet, investment posting, or plan.
create or replace function public.mutate_installment_paid_cycle(
    p_cycle jsonb, p_expected_version bigint, p_expected_presence boolean,
    p_expected_plan jsonb, p_expected_ledger jsonb, p_expected_wallet jsonb,
    p_expected_siblings jsonb
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
    actor uuid:=auth.uid();
    c public.due_occurrence_records%rowtype;
    old_c public.due_occurrence_records%rowtype;
    saved public.due_occurrence_records%rowtype;
    ep public.installment_plans%rowtype; actual_p public.installment_plans%rowtype;
    el public.ledger_transactions%rowtype; actual_l public.ledger_transactions%rowtype;
    ew public.ledger_wallets%rowtype; actual_w public.ledger_wallets%rowtype;
    sibling public.due_occurrence_records%rowtype;
    item jsonb; current_members jsonb; expected_members jsonb;
    deleting boolean; has_ledger boolean; has_wallet boolean;
    currency text;
begin
    if actor is null then raise exception 'installment_payment_authentication_required'; end if;
    if jsonb_typeof(p_cycle) is distinct from 'object'
       or jsonb_typeof(p_expected_plan) is distinct from 'object'
       or jsonb_typeof(p_expected_siblings) is distinct from 'array'
       or p_expected_version is null or p_expected_version not between 0 and 9223372036854775806
       or p_expected_presence is null or (not p_expected_presence and p_expected_version<>0)
       or jsonb_array_length(p_expected_siblings)>10000
       or octet_length(p_expected_siblings::text)>1048576 then
        raise exception 'installment_payment_invalid_group';
    end if;
    p_expected_ledger:=nullif(p_expected_ledger,'null'::jsonb);
    p_expected_wallet:=nullif(p_expected_wallet,'null'::jsonb);
    if (p_expected_ledger is not null and jsonb_typeof(p_expected_ledger)<>'object')
       or (p_expected_wallet is not null and jsonb_typeof(p_expected_wallet)<>'object') then
        raise exception 'installment_payment_invalid_group';
    end if;
    begin
        c:=jsonb_populate_record(null::public.due_occurrence_records,p_cycle);
        ep:=jsonb_populate_record(null::public.installment_plans,p_expected_plan);
        if p_expected_ledger is not null then el:=jsonb_populate_record(null::public.ledger_transactions,p_expected_ledger); end if;
        if p_expected_wallet is not null then ew:=jsonb_populate_record(null::public.ledger_wallets,p_expected_wallet); end if;
    exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
        raise exception 'installment_payment_invalid_group';
    end;
    -- jsonb_populate_record casts primitives and ignores unknown keys. Neither
    -- behavior may silently authorize a compared observation supplied by a caller.
    for item in
        select jsonb_build_array(p_cycle,to_jsonb(c))
        union all select jsonb_build_array(p_expected_plan,to_jsonb(ep))
        union all select jsonb_build_array(p_expected_ledger,to_jsonb(el)) where p_expected_ledger is not null
        union all select jsonb_build_array(p_expected_wallet,to_jsonb(ew)) where p_expected_wallet is not null
    loop
        if exists(select 1 from jsonb_each(item->0) f where not ((item->1) ? f.key)
            or jsonb_typeof(f.value) is distinct from jsonb_typeof(item->1->f.key)) then
            raise exception 'installment_payment_invalid_group';
        end if;
    end loop;
    if c.id is null or c.user_id is null or c.source_id is null or c.linked_transaction_id is null
       or c.source_kind_raw_value is distinct from 'installment' or c.status_raw_value is distinct from 'paid'
       or c.amount_minor_snapshot is null or c.amount_minor_snapshot<=0 or c.last_modified_by_device_id is null
       or c.created_at is null or c.updated_at is null or c.scheduled_date is null or c.paid_at is null
       or not isfinite(c.created_at) or not isfinite(c.updated_at) or not isfinite(c.scheduled_date) or not isfinite(c.paid_at)
       or (c.deleted_at is not null and not isfinite(c.deleted_at))
       or c.selected_month_key is null or c.selected_month_key !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
       or c.sync_version is distinct from p_expected_version+1
       or (select array_agg(key order by key) from jsonb_object_keys(p_cycle) key)
          is distinct from (select array_agg(key order by key) from jsonb_object_keys(to_jsonb(c)) key)
       or jsonb_typeof(p_cycle->'amount_minor_snapshot') is distinct from 'number'
       or (p_cycle->>'amount_minor_snapshot') !~ '^[0-9]+$'
       or jsonb_typeof(p_cycle->'sync_version') is distinct from 'number'
       or (p_cycle->>'sync_version') !~ '^[0-9]+$'
       or p_cycle->>'id' is distinct from c.id::text or p_cycle->>'user_id' is distinct from c.user_id::text
       or p_cycle->>'source_id' is distinct from c.source_id::text or p_cycle->>'linked_transaction_id' is distinct from c.linked_transaction_id::text
       or p_cycle->>'last_modified_by_device_id' is distinct from c.last_modified_by_device_id::text then
        raise exception 'installment_payment_invalid_group';
    end if;
    if actor<>c.user_id then raise exception 'installment_payment_owner_required'; end if;
    deleting:=c.deleted_at is not null;
    -- Match the owner cash workflow's lock ordering. Generic ledger updates also
    -- acquire the ledger before balance-trigger wallet updates.
    perform pg_advisory_xact_lock(hashtextextended(c.user_id::text||':investment-cash',0));
    select * into actual_l from public.ledger_transactions where id=c.linked_transaction_id for update;
    has_ledger:=actual_l.id is not null;
    if (has_ledger is distinct from (p_expected_ledger is not null))
       or (has_ledger and (actual_l.user_id<>c.user_id or el.id is distinct from actual_l.id
           or el.user_id is distinct from c.user_id or to_jsonb(el) is distinct from to_jsonb(actual_l))) then
        raise exception 'installment_payment_ledger_changed';
    end if;
    if has_ledger then
        select * into actual_w from public.ledger_wallets where id=actual_l.source_wallet_id for update;
    end if;
    has_wallet:=actual_w.id is not null;
    if p_expected_wallet is not null then
        if not has_wallet or ew.id is distinct from actual_w.id or ew.user_id is distinct from c.user_id or actual_w.user_id<>c.user_id
           or ew.sync_version is distinct from actual_w.sync_version or ew.created_at is distinct from actual_w.created_at
           or ew.currency_code is distinct from actual_w.currency_code or ew.kind_raw_value is distinct from actual_w.kind_raw_value
           or ew.deleted_at is distinct from actual_w.deleted_at or ew.is_archived is distinct from actual_w.is_archived then
            raise exception 'installment_payment_wallet_changed';
        end if;
    elsif not deleting then raise exception 'installment_payment_wallet_changed';
    end if;
    select * into actual_p from public.installment_plans where id=c.source_id for update;
    if actual_p.id is null or actual_p.user_id<>c.user_id or ep.id is distinct from actual_p.id or ep.user_id is distinct from c.user_id
       or to_jsonb(ep) is distinct from to_jsonb(actual_p) or actual_p.deleted_at is not null then
        raise exception 'installment_payment_source_changed';
    end if;
    if (not deleting and actual_p.is_archived) then raise exception 'installment_payment_source_changed'; end if;
    -- Calendar selection is captured/validated by the client's ZoneId planner.
    -- Never reinterpret its local midnight as the server's UTC due-day.
    if not deleting then
        currency:=upper(btrim(actual_p.currency_code));
        if not has_ledger or actual_l.deleted_at is not null or actual_l.is_archived
           or actual_l.primary_kind_raw_value<>'expense' or actual_l.entry_status_raw_value<>'posted'
           or actual_l.transfer_subtype_raw_value is not null or actual_l.debt_intent_raw_value is not null
           or actual_l.settlement_group_id is not null or actual_l.settlement_obligation_id is not null or actual_l.settlement_role_raw_value is not null
           or actual_l.reporting_expense_minor is not null or actual_l.reporting_income_minor is not null
           or actual_l.amount_minor<>c.amount_minor_snapshot or actual_l.amount_minor<=0 or actual_l.occurred_at<>c.paid_at
           or not has_wallet or actual_w.user_id<>c.user_id or actual_w.deleted_at is not null
           or actual_w.kind_raw_value not in ('cash','payPay','bank','eWallet','prepaid','crypto','other') or actual_w.system_purpose_raw_value is not null
           or currency !~ '^[A-Z]{3}$' or upper(btrim(actual_w.currency_code)) is distinct from currency
           or upper(btrim(actual_l.source_currency_code)) is distinct from currency then
            raise exception 'installment_payment_invalid_financial_footprint';
        end if;
    elsif has_ledger and actual_l.deleted_at is null then
        raise exception 'installment_payment_ledger_changed';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('installment-cycle:'||c.user_id::text||':'||c.source_id::text||':'||c.selected_month_key,0));
    -- Global target identity is compared even when RLS would hide a foreign row.
    select * into old_c from public.due_occurrence_records where id=c.id for update;
    if (old_c.id is not null) is distinct from p_expected_presence
       or (old_c.id is not null and (old_c.user_id<>c.user_id or old_c.sync_version<>p_expected_version)) then
        raise exception 'installment_payment_version_conflict';
    end if;
    if old_c.id is not null and (old_c.created_at is distinct from c.created_at or old_c.source_kind_raw_value<>'installment'
       or old_c.source_id<>c.source_id or old_c.selected_month_key<>c.selected_month_key
       or (old_c.linked_transaction_id is not null and old_c.linked_transaction_id<>c.linked_transaction_id)) then
        raise exception 'installment_payment_invalid_identity';
    end if;
    perform 1 from public.due_occurrence_records where user_id=c.user_id and source_kind_raw_value='installment'
        and source_id=c.source_id and selected_month_key=c.selected_month_key order by id for update;
    if (select count(distinct value->>'id') from jsonb_array_elements(p_expected_siblings))<>jsonb_array_length(p_expected_siblings) then
        raise exception 'installment_payment_invalid_group';
    end if;
    for item in select value from jsonb_array_elements(p_expected_siblings) loop
        if jsonb_typeof(item)<>'object' then raise exception 'installment_payment_invalid_group'; end if;
        sibling:=jsonb_populate_record(null::public.due_occurrence_records,item);
        if sibling.id is null or sibling.user_id is distinct from c.user_id or sibling.source_kind_raw_value is distinct from 'installment'
           or sibling.source_id is distinct from c.source_id or sibling.selected_month_key is distinct from c.selected_month_key
           or exists(select 1 from jsonb_each(item) f where jsonb_typeof(f.value) is distinct from jsonb_typeof(to_jsonb(sibling)->f.key))
           or (select array_agg(key order by key) from jsonb_object_keys(item) key) is distinct from
              (select array_agg(key order by key) from jsonb_object_keys(to_jsonb(sibling)) key) then
            raise exception 'installment_payment_invalid_group';
        end if;
    end loop;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into expected_members
        from jsonb_populate_recordset(null::public.due_occurrence_records,p_expected_siblings) x;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into current_members
        from public.due_occurrence_records x where x.user_id=c.user_id and x.source_kind_raw_value='installment'
        and x.source_id=c.source_id and x.selected_month_key=c.selected_month_key;
    if current_members<>expected_members then raise exception 'installment_payment_membership_changed'; end if;
    if exists(select 1 from public.due_occurrence_records x where x.user_id=c.user_id and x.id<>c.id and x.deleted_at is null
       and ((x.source_kind_raw_value='installment' and x.source_id=c.source_id and x.selected_month_key=c.selected_month_key)
            or x.linked_transaction_id=c.linked_transaction_id)) then
        raise exception 'installment_payment_financial_sibling_conflict';
    end if;
    insert into public.due_occurrence_records as target
        (id,user_id,source_kind_raw_value,source_id,selected_month_key,scheduled_date,amount_minor_snapshot,status_raw_value,paid_at,linked_transaction_id,created_at,updated_at,deleted_at,sync_version,last_modified_by_device_id)
    values (c.id,c.user_id,c.source_kind_raw_value,c.source_id,c.selected_month_key,c.scheduled_date,c.amount_minor_snapshot,c.status_raw_value,c.paid_at,c.linked_transaction_id,c.created_at,c.updated_at,c.deleted_at,c.sync_version,c.last_modified_by_device_id)
    on conflict(id) do update set
        scheduled_date=excluded.scheduled_date,amount_minor_snapshot=excluded.amount_minor_snapshot,status_raw_value=excluded.status_raw_value,
        paid_at=excluded.paid_at,linked_transaction_id=excluded.linked_transaction_id,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at,
        sync_version=excluded.sync_version,last_modified_by_device_id=excluded.last_modified_by_device_id
    where p_expected_presence and target.user_id=c.user_id and target.sync_version=p_expected_version
        and target.created_at=c.created_at and target.source_kind_raw_value='installment'
        and target.source_id=c.source_id and target.selected_month_key=c.selected_month_key
    returning * into saved;
    if not found then raise exception 'installment_payment_version_conflict'; end if;
    return to_jsonb(saved);
end;
$$;
revoke all on function public.mutate_installment_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb,jsonb) from public, anon, service_role;
grant execute on function public.mutate_installment_paid_cycle(jsonb,bigint,boolean,jsonb,jsonb,jsonb,jsonb) to authenticated;
