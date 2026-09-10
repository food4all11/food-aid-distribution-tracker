create or replace function log_distribution_freetext(
  p_location        text,
  p_organisation    text,
  p_distributed_on  date,
  p_food_category   text,
  p_postal_code     text default null,
  p_notes           text default null,
  p_logged_by       text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_block_id bigint;
  v_org_id   bigint;
  v_norm     text := normalise_street_words(p_location);
  v_digits   text := nullif(regexp_replace(coalesce(p_postal_code,''), '[^0-9]', '', 'g'), '');
  v_matches  int;
  v_reason   text;
  v_allowed  text[] := array[
    'Canned food','Fresh vegetables','Fresh fruit',
    'Dry food (rice, noodles, biscuits)','Bread and bakery',
    'Dairy and milk powder','Hot meals','Household essentials','Mixed bundle'];
  v_cat      text;
begin
  select a into v_cat from unnest(v_allowed) a
  where lower(a) = lower(trim(coalesce(p_food_category,''))) limit 1;

  if v_digits is not null then
    select b.id into v_block_id from blocks b
    where regexp_replace(coalesce(b.postal_code,''), '[^0-9]', '', 'g') = v_digits limit 1;
  end if;

  if v_block_id is null then
    select b.id into v_block_id from blocks b
    where normalise_street_words(b.block_no || ' ' || b.street) = v_norm limit 1;
  end if;

  if v_block_id is null and v_norm ~ '^[0-9]+[a-z]?$' then
    select count(*) into v_matches from blocks b where lower(b.block_no) = v_norm;
    if v_matches = 1 then
      select b.id into v_block_id from blocks b where lower(b.block_no) = v_norm;
    elsif v_matches > 1 then
      v_reason := 'Block number "' || v_norm || '" matches more than one street.';
    end if;
  end if;

  select o.id into v_org_id from organisations o
  where lower(trim(p_organisation)) = lower(o.name) limit 1;

  if v_block_id is null or v_org_id is null or v_cat is null then
    insert into pending_distributions (
      raw_location, raw_postal_code, raw_organisation, distributed_on,
      food_category, notes, logged_by, reason
    ) values (
      p_location, p_postal_code, p_organisation, p_distributed_on,
      p_food_category, p_notes, p_logged_by,
      coalesce(v_reason,
        case when v_cat is null and v_block_id is null
               then 'Food type "' || coalesce(p_food_category,'') || '" not recognised, and location not found.'
             when v_cat is null
               then 'Food type "' || coalesce(p_food_category,'') || '" is not one of the nine categories.'
             when v_block_id is null and v_org_id is null
               then 'Location and organisation both unrecognised.'
             when v_block_id is null
               then 'Location not recognised. Add the block, then resolve.'
             else 'Organisation not recognised.' end)
    );
    return 'pending';
  end if;

  insert into distributions (
    block_id, organisation_id, distributed_on, food_category, notes, logged_by
  ) values (
    v_block_id, v_org_id, p_distributed_on, v_cat, p_notes, p_logged_by
  )
  on conflict (block_id, organisation_id, distributed_on, food_category)
  do update set
    notes     = coalesce(excluded.notes,     distributions.notes),
    logged_by = coalesce(excluded.logged_by, distributions.logged_by);

  return 'saved';
end;
$$;

grant execute on function log_distribution_freetext(
  text, text, date, text, text, text, text
) to anon, authenticated;
