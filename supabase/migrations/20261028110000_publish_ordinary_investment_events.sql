-- Closed ordinary transaction + derived investment cash lifecycle. Existing APIs
-- and ordinary RLS are unchanged; this entry point supplies no generic ledger writer.
create or replace function public.mutate_ordinary_investment_event(
    p_transaction jsonb,
    p_adjustment jsonb,
    p_postings jsonb,
    p_expected_version bigint,
    p_expected_adjustment_version bigint,
    p_expected_posting_versions jsonb,
    p_expected_presence jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    actor uuid := auth.uid();
    v_owner_id uuid;
    v_event_id uuid;
    adjustment_id uuid;
    root_id uuid;
    currency text;
    t public.ledger_transactions%rowtype;
    a public.ledger_transactions%rowtype;
    old_t public.ledger_transactions%rowtype;
    old_a public.ledger_transactions%rowtype;
    old_p public.investment_wallet_postings%rowtype;
    p public.investment_wallet_postings%rowtype;
    w public.ledger_wallets%rowtype;
    saved_t public.ledger_transactions%rowtype;
    saved_a public.ledger_transactions%rowtype;
    saved_p public.investment_wallet_postings%rowtype;
    item jsonb;
    component text;
    components text[] := array['cash-consumption-booked','cash-consumption-unreconciled','cash-destination-booked','cash-destination-unreconciled'];
    expected bigint;
    ids uuid[];
    wallet_ids uuid[];
    proposed_destination uuid;
    active_parent boolean;
    consumed numeric := 0;
    unreconciled numeric := 0;
    pair jsonb;
    saved_postings jsonb := '[]'::jsonb;
    balance record;
begin
    if actor is null then raise exception 'ordinary_investment_authentication_required'; end if;
    if jsonb_typeof(p_transaction) is distinct from 'object'
       or jsonb_typeof(p_postings) is distinct from 'array'
       or jsonb_array_length(p_postings) not between 1 and 4
       or jsonb_typeof(p_expected_posting_versions) is distinct from 'object'
       or jsonb_typeof(p_expected_presence) is distinct from 'object'
       or p_expected_version is null or p_expected_version not between 0 and 9223372036854775806
       or p_expected_adjustment_version is null or p_expected_adjustment_version not between 0 and 9223372036854775806 then
        raise exception 'ordinary_investment_invalid_group';
    end if;
    p_adjustment := nullif(p_adjustment,'null'::jsonb);
    if p_adjustment is not null and jsonb_typeof(p_adjustment) <> 'object' then
        raise exception 'ordinary_investment_invalid_group';
    end if;
    t := jsonb_populate_record(null::public.ledger_transactions,p_transaction);
    v_owner_id:=t.user_id; v_event_id:=t.id;
    if v_owner_id is null or v_event_id is null then raise exception 'ordinary_investment_invalid_group'; end if;
    adjustment_id:=public.investment_ledger_id(v_event_id,'cash-unreconciled-adjustment');
    root_id:=public.investment_system_wallet_id(v_owner_id);
    if (select count(distinct value->>'id') from jsonb_array_elements(p_postings))<>jsonb_array_length(p_postings) then raise exception 'ordinary_investment_incomplete_group'; end if;
    -- Presence disambiguates a real observed legacy version0 from an absent ID.
    -- It is a comparison, never authority to overwrite a foreign global identity.
    if (select count(*) from jsonb_each(p_expected_presence))<>1+jsonb_array_length(p_postings)+(case when p_adjustment is null then 0 else 1 end)
       or exists(select 1 from jsonb_each(p_expected_presence) e where jsonb_typeof(e.value) is distinct from 'boolean') then
        raise exception 'ordinary_investment_invalid_presence';
    end if;
    for item in select p_transaction union all select p_adjustment where p_adjustment is not null union all select value from jsonb_array_elements(p_postings)
    loop
        if jsonb_typeof(p_expected_presence->(item->>'id')) is distinct from 'boolean' then raise exception 'ordinary_investment_invalid_presence'; end if;
    end loop;
    if (p_expected_version>0 and (p_expected_presence->>v_event_id::text)::boolean is not true)
       or (p_adjustment is not null and p_expected_adjustment_version>0 and (p_expected_presence->>adjustment_id::text)::boolean is not true) then
        raise exception 'ordinary_investment_invalid_presence';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(v_owner_id::text || ':investment-cash',0));
    if not public.has_investment_permission(v_owner_id,'edit') then raise exception 'ordinary_investment_permission_required'; end if;
    -- Global identities, not owner-filtered reads: a foreign winner is a conflict.
    perform 1 from public.ledger_transactions where id in (v_event_id,adjustment_id) order by id for update;
    select * into old_t from public.ledger_transactions where id=v_event_id;
    select * into old_a from public.ledger_transactions where id=adjustment_id;
    if (old_t.id is not null and old_t.user_id is distinct from v_owner_id)
       or (old_a.id is not null and old_a.user_id is distinct from v_owner_id) then
        raise exception 'ordinary_investment_invalid_identity';
    end if;
    if coalesce(old_t.sync_version,0) <> p_expected_version
       or coalesce(old_a.sync_version,0) <> p_expected_adjustment_version
       or (old_t.id is not null) is distinct from (p_expected_presence->>v_event_id::text)::boolean
       or (old_a.id is not null) is distinct from coalesce((p_expected_presence->>adjustment_id::text)::boolean,false) then
        raise exception 'ordinary_investment_version_conflict';
    end if;
    -- Ordinary lifecycle only. Never relabel a bill, installment, trade or settlement.
    for item in select x from unnest(array[p_transaction,case when old_t.id is not null then to_jsonb(old_t) end]) x where x is not null
    loop
        if item->>'settlement_group_id' is not null or item->>'settlement_obligation_id' is not null
           or item->>'settlement_role_raw_value' is not null or item->>'reporting_expense_minor' is not null
           or item->>'reporting_income_minor' is not null
           or coalesce(item->>'entry_status_raw_value','') not in ('posted','draft')
           or (
               (item->>'primary_kind_raw_value' in ('expense','income') and item->>'transfer_subtype_raw_value' is null and item->>'debt_intent_raw_value' is null)
               or (item->>'primary_kind_raw_value'='transfer' and item->>'transfer_subtype_raw_value'='internalTransfer' and item->>'debt_intent_raw_value' is null)
               or (item->>'primary_kind_raw_value'='transfer' and item->>'transfer_subtype_raw_value'='debt' and item->>'debt_intent_raw_value'='lend' and item->>'entry_status_raw_value'='posted')
           ) is not true then raise exception 'ordinary_investment_invalid_parent'; end if;
    end loop;
    if t.last_modified_by_user_id is distinct from actor
       or t.created_by_user_id is null
       or (old_t.id is null and t.created_by_user_id is distinct from actor)
       or (old_t.id is not null and (t.created_by_user_id is distinct from old_t.created_by_user_id or t.created_at is distinct from old_t.created_at))
       or not public.transaction_category_matches_owner(t.category_id,v_owner_id)
       or (t.source_wallet_id is null and t.destination_wallet_id is null)
       or (t.source_wallet_id is not null and (not public.can_operate_wallet(t.source_wallet_id) or public.wallet_owner_user_id(t.source_wallet_id) is distinct from v_owner_id))
       or (t.destination_wallet_id is not null and (not public.can_operate_wallet(t.destination_wallet_id) or public.wallet_owner_user_id(t.destination_wallet_id) is distinct from v_owner_id))
       or (old_t.id is not null and not public.can_manage_transaction(old_t.created_by_user_id,old_t.source_wallet_id,old_t.destination_wallet_id,v_owner_id)) then
        raise exception 'ordinary_investment_permission_required';
    end if;
    if p_adjustment is null then
        if old_a.id is not null or p_expected_adjustment_version<>0 then raise exception 'ordinary_investment_incomplete_group'; end if;
    else
        a:=jsonb_populate_record(null::public.ledger_transactions,p_adjustment);
        if a.id is distinct from adjustment_id or a.user_id is distinct from v_owner_id
           or a.created_by_user_id is null or a.last_modified_by_user_id is distinct from actor
           or (old_a.id is null and a.created_by_user_id is distinct from actor)
           or (old_a.id is not null and (old_a.settlement_role_raw_value is distinct from 'investmentReserveUse' or old_a.created_by_user_id is distinct from a.created_by_user_id or old_a.created_at is distinct from a.created_at)) then
            raise exception 'ordinary_investment_invalid_adjustment';
        end if;
    end if;
    -- Exact JSON numbers and known columns; no private journals or coerced money.
    for item in select x from unnest(array[p_transaction,p_adjustment]) x where x is not null
    loop
        if exists(select 1 from jsonb_object_keys(item) k where not to_jsonb(t) ? k)
           or jsonb_typeof(item->'amount_minor') is distinct from 'number'
           or (item->>'amount_minor') !~ '^[1-9][0-9]*$'
           or (item->>'amount_minor')::numeric > 9223372036854775807
           or jsonb_typeof(item->'sync_version') is distinct from 'number'
           or (item->>'sync_version')::numeric <> (case when item->>'id'=v_event_id::text then p_expected_version else p_expected_adjustment_version end)
           or jsonb_typeof(item->'is_archived') is distinct from 'boolean'
           or item->>'created_at' is null or item->>'updated_at' is null or item->>'occurred_at' is null
           or item->>'last_modified_by_device_id' is null then raise exception 'ordinary_investment_invalid_group'; end if;
        for component in select unnest(array['destination_amount_minor','reporting_amount_minor','reporting_expense_minor','reporting_income_minor'])
        loop
            if item->>component is not null and (jsonb_typeof(item->component) is distinct from 'number' or (item->>component) !~ '^(0|[1-9][0-9]*)$' or (item->>component)::numeric>9223372036854775807) then
                raise exception 'ordinary_investment_invalid_group';
            end if;
        end loop;
    end loop;
    select array_agg(public.investment_ledger_id(v_event_id,c)) into ids from unnest(components) c;
    perform 1 from public.investment_wallet_postings where id=any(ids) or event_id=v_event_id order by id for update;
    if (select count(distinct value->>'id') from jsonb_array_elements(p_postings))<>jsonb_array_length(p_postings)
       or (select count(*) from jsonb_each(p_expected_posting_versions))<>jsonb_array_length(p_postings)
       or exists(select 1 from public.investment_wallet_postings q where (q.id=any(ids) or q.event_id=v_event_id) and not exists(select 1 from jsonb_array_elements(p_postings) x where x->>'id'=q.id::text)) then
        raise exception 'ordinary_investment_incomplete_group';
    end if;
    select array_agg(distinct x) into wallet_ids from (
        select unnest(array[root_id,t.source_wallet_id,t.destination_wallet_id,old_t.source_wallet_id,old_t.destination_wallet_id,a.source_wallet_id,a.destination_wallet_id,old_a.source_wallet_id,old_a.destination_wallet_id]) x
        union select (value->>'wallet_id')::uuid from jsonb_array_elements(p_postings)
        union select q.wallet_id from public.investment_wallet_postings q where q.id=any(ids)
    ) z where x is not null;
    perform 1 from public.ledger_wallets where id=any(wallet_ids) order by id for update;
    select currency_code into currency from public.ledger_wallets where id=root_id and user_id=v_owner_id and kind_raw_value='investment' and system_purpose_raw_value='investmentProfit' and deleted_at is null and not is_archived;
    if currency is null then raise exception 'ordinary_investment_invalid_wallet'; end if;
    foreach root_id in array wallet_ids
    loop
        select * into w from public.ledger_wallets where id=root_id;
        if w.id is null or w.user_id is distinct from v_owner_id or w.deleted_at is not null or w.is_archived
           or (w.id<>public.investment_system_wallet_id(v_owner_id) and (w.system_purpose_raw_value is not null or w.kind_raw_value='investment' or not public.can_operate_wallet(w.id))) then
            raise exception 'ordinary_investment_invalid_wallet';
        end if;
    end loop;
    root_id:=public.investment_system_wallet_id(v_owner_id);
    if t.source_wallet_id=root_id or t.destination_wallet_id=root_id then raise exception 'ordinary_investment_invalid_wallet'; end if;
    active_parent:=t.deleted_at is null and not t.is_archived and t.entry_status_raw_value='posted' and t.primary_kind_raw_value<>'income';
    if t.primary_kind_raw_value='transfer' and t.transfer_subtype_raw_value='internalTransfer' then
        select id into proposed_destination from public.ledger_wallets where id=t.destination_wallet_id and kind_raw_value<>'creditCard';
    end if;
    for item in select value from jsonb_array_elements(p_postings) order by value->>'id'
    loop
        p:=jsonb_populate_record(null::public.investment_wallet_postings,item);
        select c into component from unnest(components) c where public.investment_ledger_id(v_event_id,c)=p.id;
        if component is null or p.user_id is distinct from v_owner_id or p.event_id is distinct from v_event_id or p.ledger_transaction_id is distinct from v_event_id
           or p.wallet_id is null or p.trade_id is not null or p.asset_id is not null or p.cash_origin_raw_value is distinct from 'derived'
           or p.currency_code is distinct from currency or p.accounting_currency_code is distinct from currency
           or p.amount_minor is distinct from p.accounting_amount_minor or p.amount_minor=0 or p.amount_minor=-9223372036854775808
           or p.occurred_at is null or p.created_at is null or p.updated_at is null or p.last_modified_by_device_id is null
           or exists(select 1 from jsonb_object_keys(item) k where not to_jsonb(p) ? k)
           or jsonb_typeof(item->'amount_minor') is distinct from 'number' or (item->>'amount_minor') !~ '^-?[1-9][0-9]*$'
           or jsonb_typeof(item->'accounting_amount_minor') is distinct from 'number' or (item->>'accounting_amount_minor') !~ '^-?[1-9][0-9]*$'
           or jsonb_typeof(item->'sync_version') is distinct from 'number'
           or jsonb_typeof(p_expected_posting_versions->(p.id::text)) is distinct from 'number'
           or (p_expected_posting_versions->>p.id::text) !~ '^(0|[1-9][0-9]*)$'
           or (p_expected_posting_versions->>p.id::text)::numeric>9223372036854775806 then
            raise exception 'ordinary_investment_invalid_posting';
        end if;
        expected:=(p_expected_posting_versions->>p.id::text)::bigint;
        if p.sync_version is distinct from expected then raise exception 'ordinary_investment_invalid_posting'; end if;
        if expected>0 and (p_expected_presence->>p.id::text)::boolean is not true then raise exception 'ordinary_investment_invalid_presence'; end if;
        select * into old_p from public.investment_wallet_postings where id=p.id;
        if old_p.id is not null and (old_p.user_id is distinct from v_owner_id or old_p.event_id is distinct from v_event_id or old_p.ledger_transaction_id is distinct from v_event_id or old_p.created_at is distinct from p.created_at) then
            raise exception 'ordinary_investment_invalid_identity';
        end if;
        if coalesce(old_p.sync_version,0)<>expected or (old_p.id is not null) is distinct from (p_expected_presence->>p.id::text)::boolean then raise exception 'ordinary_investment_version_conflict'; end if;
        select * into w from public.ledger_wallets where id=p.wallet_id;
        if w.kind_raw_value in ('investment','creditCard') or w.currency_code is distinct from currency or w.system_purpose_raw_value is not null then raise exception 'ordinary_investment_invalid_wallet'; end if;
        if p.cash_bucket_raw_value is distinct from (case when component='cash-consumption-unreconciled' then 'unreconciled' else 'booked' end)
           or (component like 'cash-consumption-%' and (p.amount_minor>=0 or p.role_raw_value not in ('cashConsumption','cashTransfer')))
           or (component like 'cash-destination-%' and (p.amount_minor<=0 or p.role_raw_value is distinct from 'cashTransfer')) then raise exception 'ordinary_investment_invalid_posting'; end if;
        if p.deleted_at is null then
            if not active_parent or p.occurred_at is distinct from t.occurred_at then raise exception 'ordinary_investment_invalid_posting'; end if;
            if component like 'cash-consumption-%' then
                if p.wallet_id is distinct from t.source_wallet_id or t.source_currency_code is distinct from currency
                   or p.role_raw_value is distinct from (case when proposed_destination is null then 'cashConsumption' else 'cashTransfer' end) then raise exception 'ordinary_investment_invalid_posting'; end if;
                consumed:=consumed-p.accounting_amount_minor;
                if component='cash-consumption-unreconciled' then unreconciled:=-p.accounting_amount_minor; end if;
            else
                if proposed_destination is null or p.wallet_id is distinct from proposed_destination or t.destination_currency_code is distinct from currency then raise exception 'ordinary_investment_invalid_posting'; end if;
            end if;
            select value into pair from jsonb_array_elements(p_postings) where value->>'id'=public.investment_ledger_id(v_event_id,case when component like 'cash-consumption-%' then replace(component,'cash-consumption-','cash-destination-') else replace(component,'cash-destination-','cash-consumption-') end)::text and value->>'deleted_at' is null;
            if proposed_destination is not null and (pair is null or (pair->>'accounting_amount_minor')::numeric<>-p.accounting_amount_minor::numeric) then raise exception 'ordinary_investment_invalid_posting'; end if;
        end if;
    end loop;
    if consumed>t.amount_minor then raise exception 'ordinary_investment_invalid_posting'; end if;
    if consumed>0 and proposed_destination is not null and (t.source_wallet_id=t.destination_wallet_id or t.destination_amount_minor is distinct from t.amount_minor) then raise exception 'ordinary_investment_invalid_posting'; end if;
    if p_adjustment is null then
        if unreconciled<>0 then raise exception 'ordinary_investment_invalid_adjustment'; end if;
    else
        if a.primary_kind_raw_value is distinct from 'transfer' or a.transfer_subtype_raw_value is distinct from 'internalTransfer'
           or a.entry_status_raw_value is distinct from 'posted' or a.settlement_role_raw_value is distinct from 'investmentReserveUse'
           or a.source_wallet_id is distinct from root_id or a.is_archived or a.archived_at is not null
           or a.source_currency_code is distinct from currency or a.destination_currency_code is distinct from currency or a.reporting_currency_code is distinct from currency
           or a.amount_minor is distinct from a.destination_amount_minor or a.amount_minor is distinct from a.reporting_amount_minor
           or a.reporting_expense_minor is distinct from 0 or a.reporting_income_minor is distinct from 0
           or a.category_id is not null or a.debt_intent_raw_value is not null or a.settlement_group_id is not null or a.settlement_obligation_id is not null
           or a.conversion_mode_raw_value is not null or a.exchange_rate_decimal_string is not null or a.exchange_rate_provider is not null or a.exchange_rate_date is not null
           or a.counterparty_name is not null or a.normalized_counterparty_key is not null
           or (a.deleted_at is null and (unreconciled=0 or a.amount_minor<>unreconciled or a.destination_wallet_id is distinct from t.source_wallet_id or a.occurred_at is distinct from t.occurred_at))
           or (a.deleted_at is not null and unreconciled<>0) then raise exception 'ordinary_investment_invalid_adjustment'; end if;
        select * into w from public.ledger_wallets where id=a.destination_wallet_id;
        if w.kind_raw_value in ('investment','creditCard') or w.currency_code is distinct from currency then raise exception 'ordinary_investment_invalid_adjustment'; end if;
    end if;
    -- Evaluate the final batch, including removal of a consumed positive transfer.
    -- Numeric sums avoid Int64 overflow; no row-order-dependent intermediate credit.
    for balance in
        select wallet_id,cash_bucket_raw_value,sum(amount) total from (
            select q.wallet_id,q.cash_bucket_raw_value,q.accounting_amount_minor::numeric amount from public.investment_wallet_postings q
            where q.user_id=v_owner_id and q.deleted_at is null and q.cash_bucket_raw_value is not null and not(q.id=any(ids)) and q.wallet_id=any(wallet_ids)
            union all select (x->>'wallet_id')::uuid,x->>'cash_bucket_raw_value',(x->>'accounting_amount_minor')::numeric from jsonb_array_elements(p_postings) x where x->>'deleted_at' is null
        ) all_rows group by wallet_id,cash_bucket_raw_value
    loop
        if exists(select 1 from jsonb_array_elements(p_postings) x where x->>'deleted_at' is null and x->>'wallet_id'=balance.wallet_id::text and x->>'cash_bucket_raw_value'=balance.cash_bucket_raw_value)
           or exists(select 1 from public.investment_wallet_postings q where q.id=any(ids) and q.deleted_at is null and q.wallet_id=balance.wallet_id and q.cash_bucket_raw_value=balance.cash_bucket_raw_value) then
            if balance.total<0 or balance.total>9223372036854775807 then raise exception 'ordinary_investment_capacity_conflict'; end if;
        end if;
    end loop;
    -- All comparisons precede every write. Final conflict predicates also protect
    -- an absent-row race with a legacy generic writer which lacks the owner lock.
    t.sync_version:=p_expected_version+1;
    insert into public.ledger_transactions (id, user_id, primary_kind_raw_value, transfer_subtype_raw_value, debt_intent_raw_value, entry_status_raw_value, title, note, amount_minor, source_currency_code, destination_currency_code, destination_amount_minor, reporting_currency_code, reporting_amount_minor, conversion_mode_raw_value, exchange_rate_decimal_string, exchange_rate_provider, exchange_rate_date, occurred_at, created_by_user_id, last_modified_by_user_id, counterparty_name, normalized_counterparty_key, settlement_group_id, settlement_obligation_id, settlement_role_raw_value, reporting_expense_minor, reporting_income_minor, source_wallet_id, destination_wallet_id, category_id, deleted_at, is_archived, archived_at, created_at, updated_at, sync_version, last_modified_by_device_id) values (t.id, t.user_id, t.primary_kind_raw_value, t.transfer_subtype_raw_value, t.debt_intent_raw_value, t.entry_status_raw_value, t.title, t.note, t.amount_minor, t.source_currency_code, t.destination_currency_code, t.destination_amount_minor, t.reporting_currency_code, t.reporting_amount_minor, t.conversion_mode_raw_value, t.exchange_rate_decimal_string, t.exchange_rate_provider, t.exchange_rate_date, t.occurred_at, t.created_by_user_id, t.last_modified_by_user_id, t.counterparty_name, t.normalized_counterparty_key, t.settlement_group_id, t.settlement_obligation_id, t.settlement_role_raw_value, t.reporting_expense_minor, t.reporting_income_minor, t.source_wallet_id, t.destination_wallet_id, t.category_id, t.deleted_at, t.is_archived, t.archived_at, t.created_at, t.updated_at, t.sync_version, t.last_modified_by_device_id)
        on conflict(id) do update set primary_kind_raw_value=excluded.primary_kind_raw_value,
            transfer_subtype_raw_value=excluded.transfer_subtype_raw_value,
            debt_intent_raw_value=excluded.debt_intent_raw_value,
            entry_status_raw_value=excluded.entry_status_raw_value,
            title=excluded.title,
            note=excluded.note,
            amount_minor=excluded.amount_minor,
            source_currency_code=excluded.source_currency_code,
            destination_currency_code=excluded.destination_currency_code,
            destination_amount_minor=excluded.destination_amount_minor,
            reporting_currency_code=excluded.reporting_currency_code,
            reporting_amount_minor=excluded.reporting_amount_minor,
            conversion_mode_raw_value=excluded.conversion_mode_raw_value,
            exchange_rate_decimal_string=excluded.exchange_rate_decimal_string,
            exchange_rate_provider=excluded.exchange_rate_provider,
            exchange_rate_date=excluded.exchange_rate_date,
            occurred_at=excluded.occurred_at,
            last_modified_by_user_id=excluded.last_modified_by_user_id,
            counterparty_name=excluded.counterparty_name,
            normalized_counterparty_key=excluded.normalized_counterparty_key,
            settlement_group_id=excluded.settlement_group_id,
            settlement_obligation_id=excluded.settlement_obligation_id,
            settlement_role_raw_value=excluded.settlement_role_raw_value,
            reporting_expense_minor=excluded.reporting_expense_minor,
            reporting_income_minor=excluded.reporting_income_minor,
            source_wallet_id=excluded.source_wallet_id,
            destination_wallet_id=excluded.destination_wallet_id,
            category_id=excluded.category_id,
            deleted_at=excluded.deleted_at,
            is_archived=excluded.is_archived,
            archived_at=excluded.archived_at,
            updated_at=excluded.updated_at,
            sync_version=excluded.sync_version,
            last_modified_by_device_id=excluded.last_modified_by_device_id
        where public.ledger_transactions.user_id=excluded.user_id and public.ledger_transactions.sync_version=p_expected_version and (p_expected_presence->>t.id::text)::boolean
        returning * into saved_t;
        if saved_t.id is null then raise exception 'ordinary_investment_version_conflict'; end if;
    if p_adjustment is not null then
        a.sync_version:=p_expected_adjustment_version+1;
        insert into public.ledger_transactions (id, user_id, primary_kind_raw_value, transfer_subtype_raw_value, debt_intent_raw_value, entry_status_raw_value, title, note, amount_minor, source_currency_code, destination_currency_code, destination_amount_minor, reporting_currency_code, reporting_amount_minor, conversion_mode_raw_value, exchange_rate_decimal_string, exchange_rate_provider, exchange_rate_date, occurred_at, created_by_user_id, last_modified_by_user_id, counterparty_name, normalized_counterparty_key, settlement_group_id, settlement_obligation_id, settlement_role_raw_value, reporting_expense_minor, reporting_income_minor, source_wallet_id, destination_wallet_id, category_id, deleted_at, is_archived, archived_at, created_at, updated_at, sync_version, last_modified_by_device_id) values (a.id, a.user_id, a.primary_kind_raw_value, a.transfer_subtype_raw_value, a.debt_intent_raw_value, a.entry_status_raw_value, a.title, a.note, a.amount_minor, a.source_currency_code, a.destination_currency_code, a.destination_amount_minor, a.reporting_currency_code, a.reporting_amount_minor, a.conversion_mode_raw_value, a.exchange_rate_decimal_string, a.exchange_rate_provider, a.exchange_rate_date, a.occurred_at, a.created_by_user_id, a.last_modified_by_user_id, a.counterparty_name, a.normalized_counterparty_key, a.settlement_group_id, a.settlement_obligation_id, a.settlement_role_raw_value, a.reporting_expense_minor, a.reporting_income_minor, a.source_wallet_id, a.destination_wallet_id, a.category_id, a.deleted_at, a.is_archived, a.archived_at, a.created_at, a.updated_at, a.sync_version, a.last_modified_by_device_id)
        on conflict(id) do update set primary_kind_raw_value=excluded.primary_kind_raw_value,
            transfer_subtype_raw_value=excluded.transfer_subtype_raw_value,
            debt_intent_raw_value=excluded.debt_intent_raw_value,
            entry_status_raw_value=excluded.entry_status_raw_value,
            title=excluded.title,
            note=excluded.note,
            amount_minor=excluded.amount_minor,
            source_currency_code=excluded.source_currency_code,
            destination_currency_code=excluded.destination_currency_code,
            destination_amount_minor=excluded.destination_amount_minor,
            reporting_currency_code=excluded.reporting_currency_code,
            reporting_amount_minor=excluded.reporting_amount_minor,
            conversion_mode_raw_value=excluded.conversion_mode_raw_value,
            exchange_rate_decimal_string=excluded.exchange_rate_decimal_string,
            exchange_rate_provider=excluded.exchange_rate_provider,
            exchange_rate_date=excluded.exchange_rate_date,
            occurred_at=excluded.occurred_at,
            last_modified_by_user_id=excluded.last_modified_by_user_id,
            counterparty_name=excluded.counterparty_name,
            normalized_counterparty_key=excluded.normalized_counterparty_key,
            settlement_group_id=excluded.settlement_group_id,
            settlement_obligation_id=excluded.settlement_obligation_id,
            settlement_role_raw_value=excluded.settlement_role_raw_value,
            reporting_expense_minor=excluded.reporting_expense_minor,
            reporting_income_minor=excluded.reporting_income_minor,
            source_wallet_id=excluded.source_wallet_id,
            destination_wallet_id=excluded.destination_wallet_id,
            category_id=excluded.category_id,
            deleted_at=excluded.deleted_at,
            is_archived=excluded.is_archived,
            archived_at=excluded.archived_at,
            updated_at=excluded.updated_at,
            sync_version=excluded.sync_version,
            last_modified_by_device_id=excluded.last_modified_by_device_id
        where public.ledger_transactions.user_id=excluded.user_id and public.ledger_transactions.sync_version=p_expected_adjustment_version and (p_expected_presence->>a.id::text)::boolean
        returning * into saved_a;
        if saved_a.id is null then raise exception 'ordinary_investment_version_conflict'; end if;
    end if;
    for item in select value from jsonb_array_elements(p_postings) order by value->>'id'
    loop
        p:=jsonb_populate_record(null::public.investment_wallet_postings,item);
        expected:=(p_expected_posting_versions->>p.id::text)::bigint;
        p.sync_version:=expected+1;
        insert into public.investment_wallet_postings (id, user_id, event_id, trade_id, asset_id, wallet_id, ledger_transaction_id, role_raw_value, cash_bucket_raw_value, cash_origin_raw_value, amount_minor, currency_code, accounting_amount_minor, accounting_currency_code, occurred_at, created_at, updated_at, deleted_at, sync_version, last_modified_by_device_id) values (p.id, p.user_id, p.event_id, p.trade_id, p.asset_id, p.wallet_id, p.ledger_transaction_id, p.role_raw_value, p.cash_bucket_raw_value, p.cash_origin_raw_value, p.amount_minor, p.currency_code, p.accounting_amount_minor, p.accounting_currency_code, p.occurred_at, p.created_at, p.updated_at, p.deleted_at, p.sync_version, p.last_modified_by_device_id)
        on conflict(id) do update set trade_id=excluded.trade_id,
            asset_id=excluded.asset_id,
            wallet_id=excluded.wallet_id,
            role_raw_value=excluded.role_raw_value,
            cash_bucket_raw_value=excluded.cash_bucket_raw_value,
            cash_origin_raw_value=excluded.cash_origin_raw_value,
            amount_minor=excluded.amount_minor,
            currency_code=excluded.currency_code,
            accounting_amount_minor=excluded.accounting_amount_minor,
            accounting_currency_code=excluded.accounting_currency_code,
            occurred_at=excluded.occurred_at,
            updated_at=excluded.updated_at,
            deleted_at=excluded.deleted_at,
            sync_version=excluded.sync_version,
            last_modified_by_device_id=excluded.last_modified_by_device_id
        where public.investment_wallet_postings.user_id=excluded.user_id and public.investment_wallet_postings.sync_version=expected and (p_expected_presence->>p.id::text)::boolean and public.investment_wallet_postings.event_id=excluded.event_id and public.investment_wallet_postings.ledger_transaction_id=excluded.ledger_transaction_id
        returning * into saved_p;
        if saved_p.id is null then raise exception 'ordinary_investment_version_conflict'; end if;
        saved_postings:=saved_postings||jsonb_build_array(to_jsonb(saved_p));
    end loop;
    return jsonb_build_object('transaction',to_jsonb(saved_t),'adjustment',case when saved_a.id is not null then to_jsonb(saved_a) else 'null'::jsonb end,'postings',saved_postings);
end;
$$;
revoke execute on function public.mutate_ordinary_investment_event(jsonb,jsonb,jsonb,bigint,bigint,jsonb,jsonb) from public,anon;
grant execute on function public.mutate_ordinary_investment_event(jsonb,jsonb,jsonb,bigint,bigint,jsonb,jsonb) to authenticated;
