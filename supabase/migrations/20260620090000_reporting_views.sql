-- Reporting views for GEWMS dashboard and operational summaries.
-- These views keep report calculations in Supabase instead of duplicating aggregation logic in Flutter.

create or replace view public.water_billing_monthly_summary as
select
  date_trunc('month', month_billed::date)::date as month,
  count(*)::bigint as bill_count,
  coalesce(sum(amount), 0)::numeric as total_amount,
  coalesce(sum(case when coalesce(status, 'Pending') = 'Pending' then amount else 0 end), 0)::numeric as pending_amount,
  count(*) filter (where coalesce(status, 'Pending') = 'Pending')::bigint as pending_count,
  count(*) filter (where date_paid is not null or coalesce(status, '') = 'Paid')::bigint as paid_count
from public.water_bills
where month_billed is not null
group by 1;

create or replace view public.electricity_billing_monthly_summary as
select
  date_trunc('month', month_billed::date)::date as month,
  count(*)::bigint as bill_count,
  coalesce(sum(amount), 0)::numeric as total_amount,
  coalesce(sum(case when date_paid is null then amount else 0 end), 0)::numeric as unpaid_amount,
  count(*) filter (where date_paid is null)::bigint as unpaid_count,
  count(*) filter (where date_paid is not null)::bigint as paid_count
from public.electricity_bills
where month_billed is not null
group by 1;

create or replace view public.gas_transaction_monthly_summary as
select
  date_trunc('month', coalesce(date_from, created_at)::date)::date as month,
  count(*)::bigint as transaction_count,
  count(*) filter (where coalesce(status, 'Pending') = 'Pending')::bigint as pending_count,
  count(*) filter (where coalesce(status, '') = 'Completed')::bigint as completed_count,
  count(*) filter (where coalesce(status, '') = 'Cancelled')::bigint as cancelled_count,
  count(distinct driver_id)::bigint as active_driver_count,
  count(distinct car_id)::bigint as active_vehicle_count
from public.gas_transactions
where coalesce(date_from, created_at) is not null
group by 1;

create or replace view public.driver_gas_transaction_summary as
select
  gt.driver_id,
  coalesce(max(gt.driver_name), max(d.driver_name)) as driver_name,
  count(*)::bigint as transaction_count,
  count(*) filter (where coalesce(gt.status, 'Pending') = 'Pending')::bigint as pending_count,
  count(*) filter (where coalesce(gt.status, '') = 'Completed')::bigint as completed_count,
  count(*) filter (where coalesce(gt.status, '') = 'Cancelled')::bigint as cancelled_count,
  max(coalesce(gt.date_from, gt.created_at)::date) as latest_trip_date
from public.gas_transactions gt
left join public.drivers d on d.id = gt.driver_id
group by gt.driver_id;

create or replace view public.dashboard_summary as
select
  (select count(*) from public.water_bills)::bigint as water_bill_count,
  (select coalesce(sum(amount), 0) from public.water_bills where coalesce(status, 'Pending') = 'Pending')::numeric as pending_water_amount,
  (select count(*) from public.electricity_bills)::bigint as electricity_bill_count,
  (select coalesce(sum(amount), 0) from public.electricity_bills where date_paid is null)::numeric as unpaid_electricity_amount,
  (select count(*) from public.gas_transactions)::bigint as gas_transaction_count,
  (select count(*) from public.gas_transactions where coalesce(status, 'Pending') = 'Pending')::bigint as pending_gas_transaction_count,
  (select count(*) from public.drivers)::bigint as driver_count,
  (select count(*) from public.cars)::bigint as vehicle_count;

-- RLS still applies to the underlying tables. Grant select on the views so authenticated users can query them.
grant select on public.water_billing_monthly_summary to authenticated;
grant select on public.electricity_billing_monthly_summary to authenticated;
grant select on public.gas_transaction_monthly_summary to authenticated;
grant select on public.driver_gas_transaction_summary to authenticated;
grant select on public.dashboard_summary to authenticated;
