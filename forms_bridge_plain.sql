create or replace function log_distribution(
  p_block_label     text,          -- "Blk 16 Bedok South Road"
  p_organisation    text,          -- must match organisations.name exactly
  p_distributed_on  date,
  p_food_category   text,
  p_units_prepared  integer default null,
  p_units_given_out integer default null,
  p_start_time      time    default null,
  p_end_time        time    default null,
  p_notes           text    default null,
  p_logged_by       text    default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_block_id bigint;
  v_org_id   bigint;
  v_id       bigint;
  v_label    text := trim(regexp_replace(p_block_label, '^\s*Blk\s+', '', 'i'));
begin
  select b.id into v_block_id
  from blocks b
  where lower(v_label) = lower(b.block_no || ' ' || b.street)
  limit 1;

  if v_block_id is null then
    raise exception 'No block matches "%". Check the form dropdown against the blocks table.',
      p_block_label;
  end if;

  select o.id into v_org_id
  from organisations o
  where lower(trim(p_organisation)) = lower(o.name)
  limit 1;

  if v_org_id is null then
    raise exception 'No organisation named "%".', p_organisation;
  end if;

  insert into distributions (
    block_id, organisation_id, distributed_on, start_time, end_time,
    food_category, units_prepared, units_given_out, notes, logged_by
  ) values (
    v_block_id, v_org_id, p_distributed_on, p_start_time, p_end_time,
    p_food_category, p_units_prepared, p_units_given_out, p_notes, p_logged_by
  )
  on conflict (block_id, organisation_id, distributed_on, food_category)
  do update set
    units_prepared  = coalesce(excluded.units_prepared,  distributions.units_prepared),
    units_given_out = coalesce(excluded.units_given_out, distributions.units_given_out),
    start_time      = coalesce(excluded.start_time,      distributions.start_time),
    end_time        = coalesce(excluded.end_time,        distributions.end_time),
    notes           = coalesce(excluded.notes,           distributions.notes),
    logged_by       = coalesce(excluded.logged_by,       distributions.logged_by)
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function log_distribution(
  text, text, date, text, integer, integer, time, time, text, text
) to anon, authenticated;

create or replace view form_dropdown_options as
select 'Block' as question, 'Blk ' || block_no || ' ' || street as option_text
from blocks
union all
select 'Organisation', name from organisations
union all
select 'Food category', unnest(array[
  'Canned food',
  'Fresh vegetables',
  'Fresh fruit',
  'Dry food (rice, noodles, biscuits)',
  'Bread and bakery',
  'Dairy and milk powder',
  'Hot meals',
  'Household essentials',
  'Mixed bundle'
]);
