begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

select has_schema('public', 'public schema exists');
select has_extension('pgtap', 'pgTAP extension is available');

select * from finish();

rollback;
