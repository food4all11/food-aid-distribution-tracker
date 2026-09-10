delete from distributions;
delete from organisations;
delete from blocks;
select 'blocks' as table_name, count(*) as rows_remaining from blocks
union all select 'organisations', count(*) from organisations
union all select 'distributions', count(*) from distributions;
