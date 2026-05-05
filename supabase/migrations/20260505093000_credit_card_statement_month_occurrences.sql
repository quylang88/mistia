-- Credit card due occurrences are keyed by the statement month, not the
-- payment due month. A March payment can settle the February statement, so the
-- persisted month key must keep February as the statement identity.

update public.due_occurrence_records occurrence
set
  selected_month_key = to_char(
    date_trunc('month', occurrence.scheduled_date) - interval '1 month',
    'YYYY-MM'
  ),
  updated_at = timezone('utc'::text, now())
where occurrence.source_kind_raw_value = 'creditCard'
  and occurrence.deleted_at is null
  and occurrence.selected_month_key = to_char(
    date_trunc('month', occurrence.scheduled_date),
    'YYYY-MM'
  );
