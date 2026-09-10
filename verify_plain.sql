select 'blocks' as table_name, count(*)::text as rows from blocks
union all select 'organisations', count(*)::text from organisations
union all select 'distributions', count(*)::text from distributions
union all select 'food categories in use', count(distinct food_category)::text from distributions
union all select 'blocks never served', count(*)::text from block_coverage where coverage_state = 'never recorded'
union all select 'overlapping visits', count(*)::text from overlap_watch
union all select 'form bridge installed', case when exists (
  select 1 from pg_proc where proname = 'log_distribution') then 'yes' else 'NO - run forms_bridge_plain.sql' end
union all select 'website can save', case when exists (
  select 1 from pg_policies where tablename='distributions' and cmd='INSERT'
  and roles::text like '%anon%') then 'yes' else 'NO - run the policy step' end;
