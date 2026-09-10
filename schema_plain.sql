create table if not exists blocks (
  id              bigint generated always as identity primary key,
  block_no        text not null,
  street          text not null,
  postal_code     text,
  planning_area   text not null,
  is_rental       boolean not null default true,
  approx_units    integer check (approx_units is null or approx_units > 0),
  lat             double precision not null check (lat between 1.15 and 1.50),
  lng             double precision not null check (lng between 103.6 and 104.1),
  created_at      timestamptz not null default now(),

  constraint blocks_unique_address unique (block_no, street)
);

comment on table blocks is
  'One row per HDB block in scope. Verify addresses and coordinates against '
  'HDB / OneMap before relying on them operationally.';
comment on column blocks.is_rental is
  'True for public rental flats. Kept as a flag rather than a filter on the '
  'table so that non-rental blocks can be tracked for comparison.';

create table if not exists organisations (
  id              bigint generated always as identity primary key,
  name            text not null unique,
  programme_type  text not null check (programme_type in (
                    'Soup Kitchen',
                    'Community Fridge or Vending Machine',
                    'Food or Grocery Vouchers',
                    'Food Rations',
                    'Food Rescue',
                    'Fresh Meals',
                    'Community Shop'
                  )),
  contact_name    text,
  contact_email   text,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);

create table if not exists distributions (
  id                bigint generated always as identity primary key,
  block_id          bigint not null references blocks (id) on delete restrict,
  organisation_id   bigint not null references organisations (id) on delete restrict,
  distributed_on    date not null,
  start_time        time,
  end_time          time,
  food_category     text not null check (food_category in (
                      'Canned food',
                      'Fresh vegetables',
                      'Fresh fruit',
                      'Dry food (rice, noodles, biscuits)',
                      'Bread and bakery',
                      'Dairy and milk powder',
                      'Hot meals',
                      'Household essentials',
                      'Mixed bundle'
                    )),
  units_prepared    integer check (units_prepared is null or units_prepared >= 0),
  units_given_out   integer check (units_given_out is null or units_given_out >= 0),

  surplus_units     integer generated always as (units_prepared - units_given_out) stored,

  notes             text,
  logged_by         text,
  created_at        timestamptz not null default now(),

  constraint distributions_given_not_over_prepared
    check (units_given_out is null
           or units_prepared is null
           or units_given_out <= units_prepared),

  constraint distributions_end_after_start
    check (end_time is null or start_time is null or end_time > start_time),

  constraint distributions_no_exact_duplicate
    unique (block_id, organisation_id, distributed_on, food_category)
);

create index if not exists distributions_block_date_idx
  on distributions (block_id, distributed_on desc);
create index if not exists distributions_date_idx
  on distributions (distributed_on desc);
create index if not exists distributions_org_idx
  on distributions (organisation_id);

create or replace view block_coverage as
select
  b.id,
  b.block_no,
  b.street,
  b.postal_code,
  b.planning_area,
  b.is_rental,
  b.approx_units,
  b.lat,
  b.lng,
  max(d.distributed_on)                            as last_distribution_on,
  (current_date - max(d.distributed_on))::int      as days_since_last,
  count(d.id)::int                                 as distribution_count,
  count(distinct d.organisation_id)::int           as organisation_count,
  coalesce(sum(d.units_given_out), 0)::int         as units_given_out_total,
  coalesce(sum(d.surplus_units), 0)::int           as surplus_total,
  case
    when max(d.distributed_on) is null                     then 'never recorded'
    when current_date - max(d.distributed_on) <= 14        then 'served recently'
    when current_date - max(d.distributed_on) <= 42        then 'watch'
    else                                                        'gap'
  end                                              as coverage_state
from blocks b
left join distributions d on d.block_id = b.id
group by b.id;

comment on view block_coverage is
  'Thresholds (14 / 42 days) are a starting assumption, not a finding. '
  'Replace them once you have observed the real cadence at Bedok.';

create or replace view overlap_watch as
select
  b.block_no,
  b.street,
  d1.distributed_on          as first_date,
  o1.name                    as first_org,
  d1.food_category           as first_category,
  d2.distributed_on          as second_date,
  o2.name                    as second_org,
  d2.food_category           as second_category,
  (d2.distributed_on - d1.distributed_on)::int as days_apart
from distributions d1
join distributions d2
  on d1.block_id = d2.block_id
 and d2.organisation_id <> d1.organisation_id
 and d2.distributed_on >= d1.distributed_on
 and d2.distributed_on <  d1.distributed_on + 7
 and d2.id <> d1.id
join blocks b        on b.id  = d1.block_id
join organisations o1 on o1.id = d1.organisation_id
join organisations o2 on o2.id = d2.organisation_id
order by d1.distributed_on desc;

create or replace view surplus_by_org_month as
select
  o.name                                    as organisation,
  date_trunc('month', d.distributed_on)::date as month,
  count(*)::int                             as events,
  coalesce(sum(d.units_prepared), 0)::int   as prepared,
  coalesce(sum(d.units_given_out), 0)::int  as given_out,
  coalesce(sum(d.surplus_units), 0)::int    as surplus,
  round(
    100.0 * coalesce(sum(d.surplus_units), 0)
    / nullif(sum(d.units_prepared), 0)
  , 1)                                      as surplus_pct
from distributions d
join organisations o on o.id = d.organisation_id
group by o.name, date_trunc('month', d.distributed_on)
order by month desc, surplus desc;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
end
$$;

alter table blocks         enable row level security;
alter table organisations  enable row level security;
alter table distributions  enable row level security;

create policy "blocks readable by anyone"
  on blocks for select using (true);
create policy "organisations readable by anyone"
  on organisations for select using (true);
create policy "distributions readable by anyone"
  on distributions for select using (true);

create policy "signed-in users may log a distribution"
  on distributions for insert to authenticated with check (true);
create policy "signed-in users may correct a distribution"
  on distributions for update to authenticated using (true) with check (true);
