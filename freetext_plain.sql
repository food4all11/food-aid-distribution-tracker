-- ============================================================
-- Free-text location entry
--
-- Lets volunteers type where they were instead of picking from a
-- dropdown. Anything that cannot be matched to a known block is
-- parked in `pending_distributions` for someone to resolve later,
-- rather than being rejected and lost.
--
-- Run AFTER schema.sql and forms_bridge.sql.
-- ============================================================


-- ------------------------------------------------------------
-- Holding area for submissions we could not place on the map.
-- ------------------------------------------------------------
create table if not exists pending_distributions (
  id                bigint generated always as identity primary key,
  raw_location      text not null,
  raw_postal_code   text,
  raw_organisation  text not null,
  distributed_on    date not null,
  food_category     text not null,
  notes             text,
  logged_by         text,
  reason            text,
  resolved          boolean not null default false,
  created_at        timestamptz not null default now()
);

create index if not exists pending_unresolved_idx
  on pending_distributions (resolved, created_at desc);

alter table pending_distributions enable row level security;

drop policy if exists "pending readable by anyone" on pending_distributions;
drop policy if exists "anyone may submit a pending record" on pending_distributions;
drop policy if exists "signed-in users may resolve pending records" on pending_distributions;

create policy "pending readable by anyone"
  on pending_distributions for select using (true);
create policy "anyone may submit a pending record"
  on pending_distributions for insert to anon, authenticated with check (true);
create policy "signed-in users may resolve pending records"
  on pending_distributions for update to authenticated using (true) with check (true);


-- ------------------------------------------------------------
-- Normalise messy location text so "Blk 16, Bedok Sth Rd",
-- "16 bedok south road" and "BLOCK 16 BEDOK SOUTH RD" all
-- reduce to the same string.
-- ------------------------------------------------------------
create or replace function normalise_location(p text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(coalesce(p, '')), '[^a-z0-9 ]', ' ', 'g'),
        '\m(blk|block)\M', ' ', 'g'),
      '\m(rd)\M',  'road',   'g'),
    '\s+', ' ', 'g'))
$$;

create or replace function normalise_street_words(p text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    regexp_replace(
      regexp_replace(normalise_location(p), '\mave\M',  'avenue', 'g'),
      '\mst\M',  'street', 'g'),
    '\msth\M', 'south',  'g')
$$;


-- ------------------------------------------------------------
-- Replaces the dropdown-only version. Tries, in order:
--   1. postal code exact match  (most reliable in Singapore)
--   2. normalised "block + street" match
--   3. block number alone, if it is unambiguous in the data
-- Anything else goes to pending_distributions.
-- ------------------------------------------------------------
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
begin
  -- 1. postal code
  if v_digits is not null then
    select b.id into v_block_id from blocks b
    where regexp_replace(coalesce(b.postal_code,''), '[^0-9]', '', 'g') = v_digits
    limit 1;
  end if;

  -- 2. normalised block + street
  if v_block_id is null then
    select b.id into v_block_id from blocks b
    where normalise_street_words(b.block_no || ' ' || b.street) = v_norm
    limit 1;
  end if;

  -- 3. bare block number, only if unambiguous
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

  if v_block_id is null or v_org_id is null then
    insert into pending_distributions (
      raw_location, raw_postal_code, raw_organisation, distributed_on,
      food_category, notes, logged_by, reason
    ) values (
      p_location, p_postal_code, p_organisation, p_distributed_on,
      p_food_category, p_notes, p_logged_by,
      coalesce(v_reason,
        case when v_block_id is null and v_org_id is null
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
    v_block_id, v_org_id, p_distributed_on, p_food_category, p_notes, p_logged_by
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


-- ------------------------------------------------------------
-- Your inbox. Anything here needs a human decision.
-- ------------------------------------------------------------
create or replace view pending_review as
select id, created_at::date as submitted, raw_location, raw_postal_code,
       raw_organisation, distributed_on, food_category, reason, logged_by
from pending_distributions
where not resolved
order by created_at desc;


-- ------------------------------------------------------------
-- After adding the missing block or organisation, run this with
-- the pending id to move the record into the real table.
-- ------------------------------------------------------------
create or replace function resolve_pending(p_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  r pending_distributions%rowtype;
  v_result text;
begin
  select * into r from pending_distributions where id = p_id and not resolved;
  if not found then
    return 'No unresolved record with that id.';
  end if;

  v_result := log_distribution_freetext(
    r.raw_location, r.raw_organisation, r.distributed_on,
    r.food_category, r.raw_postal_code, r.notes, r.logged_by
  );

  if v_result = 'saved' then
    update pending_distributions set resolved = true where id = p_id;
    return 'Resolved and moved into distributions.';
  end if;

  -- log_distribution_freetext created another pending row; drop the copy
  delete from pending_distributions
  where id = (select max(id) from pending_distributions);
  return 'Still cannot match it. Add the missing block or organisation first.';
end;
$$;

grant execute on function resolve_pending(bigint) to authenticated;
