alter table public.recurring_bill_plans
  add column if not exists schedule_kind_raw_value text,
  add column if not exists payment_start_day integer,
  add column if not exists payment_start_date timestamptz,
  add column if not exists has_explicit_due_date boolean,
  add column if not exists due_date timestamptz,
  add column if not exists auto_pay_enabled boolean,
  add column if not exists auto_pay_day integer,
  add column if not exists auto_pay_date timestamptz;

update public.recurring_bill_plans
set
  schedule_kind_raw_value = coalesce(schedule_kind_raw_value, 'recurring'),
  payment_start_day = coalesce(payment_start_day, due_day),
  has_explicit_due_date = coalesce(has_explicit_due_date, false),
  auto_pay_enabled = coalesce(auto_pay_enabled, false)
where
  schedule_kind_raw_value is null
  or payment_start_day is null
  or has_explicit_due_date is null
  or auto_pay_enabled is null;

alter table public.recurring_bill_plans
  add constraint recurring_bill_plans_schedule_kind_check
    check (schedule_kind_raw_value is null or schedule_kind_raw_value in ('recurring', 'oneTime')),
  add constraint recurring_bill_plans_payment_start_day_check
    check (payment_start_day is null or payment_start_day between 1 and 31),
  add constraint recurring_bill_plans_due_day_check
    check (due_day between 1 and 31),
  add constraint recurring_bill_plans_auto_pay_day_check
    check (auto_pay_day is null or auto_pay_day between 1 and 31);
