-- Local and Staging must use dummy data only.
-- Deterministic Stage 1 masters and representative awaiting-sorting lots.

insert into public.varieties (id, code, name) values
  ('a1000000-0000-0000-0000-000000000001', 'hayward', 'ヘイワード'),
  ('a1000000-0000-0000-0000-000000000002', 'koryoku', '香緑')
on conflict (id) do nothing;

insert into public.grades (id, code, display_order)
select ('a2000000-0000-0000-0000-' || lpad(ordinality::text, 12, '0'))::uuid,
       code,
       ordinality::smallint
from unnest(array['5L','4L','3L','LL','L','M','S','SS']) with ordinality as grade(code, ordinality)
on conflict (id) do nothing;

insert into public.orchards (id, code, name) values
  ('a3000000-0000-0000-0000-000000000001', 'demo-orchard', 'デモ農園')
on conflict (id) do nothing;
insert into public.orchard_plots (id, orchard_id, code, name) values
  ('a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'north-a', '北区画A')
on conflict (id) do nothing;
insert into public.trees (id, plot_id, variety_id, code, name) values
  ('a5000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'tree-01', 'デモ樹1号')
on conflict (id) do nothing;
insert into public.suppliers (id, management_code, name) values
  ('a6000000-0000-0000-0000-000000000001', 'demo-supplier', 'デモ仕入先')
on conflict (id) do nothing;
insert into public.workers (id, code, display_name) values
  ('a7000000-0000-0000-0000-000000000001', 'demo-worker', 'デモ作業者')
on conflict (id) do nothing;
insert into public.storage_locations (id, code, name, location_type) values
  ('a8000000-0000-0000-0000-000000000001', 'cold-1', '第一冷蔵庫', 'cold_storage')
on conflict (id) do nothing;
insert into public.sorting_deadline_rules (id, harvest_year, harvest_month, variety_id, deadline_days) values
  ('a9000000-0000-0000-0000-000000000001', 2027, 5, 'a1000000-0000-0000-0000-000000000001', 30),
  ('a9000000-0000-0000-0000-000000000002', 2027, 5, 'a1000000-0000-0000-0000-000000000002', 30)
on conflict (id) do nothing;

insert into public.receiving_lots (
  id, display_id, source_type, received_on, orchard_id, plot_id, tree_id, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  'aa000000-0000-0000-0000-000000000001', '受入-2027-001', 'harvest', '2027-05-01',
  'a3000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000001', 'デモ農園 北区画A',
  'a1000000-0000-0000-0000-000000000001', 48.25, 3, '2027-05-31',
  'a7000000-0000-0000-0000-000000000001'
)
on conflict (id) do nothing;

insert into public.receiving_lots (
  id, display_id, source_type, received_on, supplier_id, supplier_reference, origin_name,
  variety_id, total_weight_kg, container_count, sorting_due_on, received_by
)
values (
  'aa000000-0000-0000-0000-000000000002', '受入-2027-002', 'purchase', '2027-05-02',
  'a6000000-0000-0000-0000-000000000001', 'DEMO-PO-001', 'デモ産地',
  'a1000000-0000-0000-0000-000000000002', 36.80, 2, '2027-06-01',
  'a7000000-0000-0000-0000-000000000001'
)
on conflict (id) do nothing;
