alter table distributions alter column units_prepared drop not null;
alter table distributions alter column units_given_out drop not null;

drop view if exists surplus_by_org_month;

create or replace view food_type_by_block as
select b.block_no, b.street, d.food_category, count(*)::int as times_given,
       max(d.distributed_on) as last_given
from distributions d
join blocks b on b.id = d.block_id
group by b.block_no, b.street, d.food_category
order by b.street, b.block_no, times_given desc;

create or replace view food_type_coverage as
select b.block_no, b.street,
       count(distinct d.food_category)::int as food_types_received,
       string_agg(distinct d.food_category, ', ' order by d.food_category) as received
from blocks b
left join distributions d on d.block_id = b.id
group by b.block_no, b.street
order by food_types_received;
