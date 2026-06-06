alter table public.recurring_bill_plans
  add column if not exists is_paused boolean not null default false,
  add column if not exists paused_at timestamptz,
  add column if not exists resume_start_month timestamptz;

update public.recurring_bill_plans
set is_paused = false
where is_paused is null;
