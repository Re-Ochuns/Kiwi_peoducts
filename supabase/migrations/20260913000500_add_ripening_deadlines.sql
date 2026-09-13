begin;

-- Harvest identity is explicit; receipt/injection dates cannot identify old crops.
create table public.ripening_rules (
  id uuid primary key default gen_random_uuid(),
  harvest_year smallint not null check (harvest_year between 2000 and 9999),
  harvest_month smallint not null check (harvest_month between 1 and 12),
  variety_id uuid not null references public.varieties(id) on delete restrict,
  ethylene_temperature numeric not null check (ethylene_temperature between -50 and 100),
  ethylene_hours numeric not null check (ethylene_hours > 0 and ethylene_hours <= 720),
  rest_temperature numeric not null check (rest_temperature between -50 and 100),
  rest_days numeric not null check (rest_days > 0 and rest_days <= 365),
  shippable_days numeric not null check (shippable_days > 0 and shippable_days <= 365),
  best_before_days numeric not null check (best_before_days >= shippable_days and best_before_days <= 365),
  is_active boolean not null default true,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  unique (harvest_year,harvest_month,variety_id)
);
alter table public.ripening_rules enable row level security;
revoke all on public.ripening_rules from anon,authenticated;
grant select on public.ripening_rules to authenticated;
grant all on public.ripening_rules to service_role;
create policy ripening_rules_read on public.ripening_rules for select to authenticated
  using (private.current_user_is_active());
create trigger ripening_rules_audit before update on public.ripening_rules
  for each row execute function private.set_updated_audit_fields();

alter function private.master_table(text) rename to master_table_before_s3;
create function private.master_table(master_type_value text) returns text
language sql immutable set search_path='' as $$
  select case when master_type_value='ripening_rule' then 'ripening_rules'
    else private.master_table_before_s3(master_type_value) end;
$$;
alter function private.master_validate(text,text,jsonb,jsonb) rename to master_validate_before_s3;
create function private.master_validate(function_name_value text,master_type_value text,input jsonb,current_row jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare result jsonb; key text; value numeric; y bigint; m bigint; v uuid;
begin
  if master_type_value<>'ripening_rule' then
    return private.master_validate_before_s3(function_name_value,master_type_value,input,current_row);
  end if;
  y:=private.rpc_input_positive_int(input,'harvest_year',function_name_value='master_register');
  m:=private.rpc_input_positive_int(input,'harvest_month',function_name_value='master_register');
  v:=private.rpc_input_uuid(input,'variety_id',function_name_value='master_register');
  if function_name_value='master_register' then
    if y not between 2000 and 9999 or m not between 1 and 12 then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫年度・月が範囲外です。');
    end if;
    perform private.master_require_active_parent(master_type_value,'variety',v,'variety_id');
  elsif (y is not null and y<>(current_row->>'harvest_year')::bigint)
    or (m is not null and m<>(current_row->>'harvest_month')::bigint)
    or (v is not null and v<>(current_row->>'variety_id')::uuid) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫年度・月・品種は変更できません。');
  end if;
  result:=case when function_name_value='master_register'
    then jsonb_build_object('harvest_year',y,'harvest_month',m,'variety_id',v) else '{}'::jsonb end;
  foreach key in array array['ethylene_temperature','ethylene_hours','rest_temperature','rest_days','shippable_days','best_before_days'] loop
    if jsonb_typeof(input->key) is distinct from 'number' then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟条件を数値で指定してください。',jsonb_build_object('field',key));
    end if;
    value:=(input->>key)::numeric;
    if (key like '%temperature' and (value < -50 or value > 100))
      or (key='ethylene_hours' and (value<=0 or value>720))
      or (key like '%days' and (value<=0 or value>365)) then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟条件が範囲外です。',jsonb_build_object('field',key));
    end if;
    result:=result||jsonb_build_object(key,value);
  end loop;
  if (result->>'shippable_days')::numeric > (result->>'best_before_days')::numeric then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷可能日数は賞味期限日数以下にしてください。');
  end if;
  return result;
end;
$$;
alter function private.master_check_duplicates(text,jsonb,uuid) rename to master_check_duplicates_before_s3;
create function private.master_check_duplicates(master_type_value text,effective_row jsonb,exclude_id uuid)
returns void language plpgsql set search_path='' as $$
declare r public.ripening_rules%rowtype;
begin
  if master_type_value<>'ripening_rule' then
    perform private.master_check_duplicates_before_s3(master_type_value,effective_row,exclude_id); return;
  end if;
  select * into r from public.ripening_rules where harvest_year=(effective_row->>'harvest_year')::int
    and harvest_month=(effective_row->>'harvest_month')::int and variety_id=(effective_row->>'variety_id')::uuid
    and (exclude_id is null or id<>exclude_id);
  if found then
    perform private.rpc_fail('KW400','MASTER_DUPLICATE','同じ収穫年度・月・品種の追熟マスターがあります。',
      jsonb_build_object('field','variety_id','reason','duplicate','existing',jsonb_build_object('master_id',r.id,'is_active',r.is_active)));
  end if;
end;
$$;
alter function private.master_guard_parents_active(text,jsonb) rename to master_guard_parents_active_before_s3;
create function private.master_guard_parents_active(master_type_value text,current_row jsonb)
returns void language plpgsql set search_path='' as $$
begin
  perform private.master_guard_parents_active_before_s3(
    case when master_type_value='ripening_rule' then 'sorting_deadline_rule' else master_type_value end,current_row);
end;
$$;
alter function private.master_guard_dependents(text,uuid) rename to master_guard_dependents_before_s3;
create function private.master_guard_dependents(master_type_value text,master_id_value uuid)
returns void language plpgsql set search_path='' as $$
begin
  perform private.master_guard_dependents_before_s3(master_type_value,master_id_value);
  if master_type_value='variety' and exists(select 1 from public.ripening_rules where variety_id=master_id_value and is_active) then
    perform private.rpc_fail('KW400','MASTER_IN_USE','有効な追熟マスターが参照しています。');
  end if;
end;
$$;

alter table public.ripening_lots
  add column harvest_year smallint check (harvest_year between 2000 and 9999),
  add column harvest_month smallint check (harvest_month between 1 and 12),
  add column calculated_removal_at timestamptz,
  add column calculated_rest_end_at timestamptz,
  add column calculated_shippable_until timestamptz,
  add column calculated_best_before_at timestamptz,
  add constraint ripening_lots_harvest_pair check ((harvest_year is null)=(harvest_month is null));
alter table public.containers add column shippable_from timestamptz,
  add constraint containers_shipping_window_check check (shippable_from is null or shippable_from<=shippable_until);
alter table public.orders add column needs_review boolean not null default false;
alter table public.inventory_reservations add column needs_review boolean not null default false;
alter table public.work_tasks add column is_overdue boolean not null default false;
create index work_tasks_pending_deadline_idx on public.work_tasks(due_at) where status='pending' and not is_overdue;
-- Deadline flags are calendar-visible revisions, as are date/status changes.
drop trigger work_tasks_calendar_prepare on public.work_tasks;
create trigger work_tasks_calendar_prepare before insert or update of
  status,scheduled_at,due_at,task_details,target_url,assigned_worker_id,schedule_warning,is_overdue on public.work_tasks
for each row execute function private.enqueue_calendar_task();
drop trigger work_tasks_calendar_queue on public.work_tasks;
create trigger work_tasks_calendar_queue after insert or update of
  status,scheduled_at,due_at,task_details,target_url,assigned_worker_id,schedule_warning,is_overdue on public.work_tasks
for each row execute function private.queue_calendar_task();
-- NULL actor means an automatic deadline operation, never an impersonated user.
alter table public.change_history alter column changed_by drop not null;

create function private.calculate_ripening_dates(base_at timestamptz,snapshot jsonb)
returns table(removal_at timestamptz,rest_end_at timestamptz,shippable_until timestamptz,best_before_at timestamptz)
language sql immutable set search_path='' as $$
  select removal,rest_end,rest_end+(snapshot->>'shippable_days')::numeric*interval '24 hours',
    rest_end+(snapshot->>'best_before_days')::numeric*interval '24 hours'
  from (select removal,removal+(snapshot->>'rest_days')::numeric*interval '24 hours' as rest_end
    from (select base_at+(snapshot->>'ethylene_hours')::numeric*interval '1 hour' as removal) r) s;
$$;

-- Preserve S2 drafts without guessing a harvest; S3 injection requires a snapshot.
alter function private.ripening_plan_action(text,jsonb,uuid,uuid) rename to ripening_plan_action_before_deadlines;
create function private.ripening_plan_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; lot public.ripening_lots%rowtype; previous public.ripening_lots%rowtype;
  y bigint; m bigint; rule public.ripening_rules%rowtype; snap jsonb;
begin
  perform pg_advisory_xact_lock(53,0);
  if fn<>'ripening_plan_register' then
    select * into previous from public.ripening_lots where id=private.rpc_input_uuid(input_value,'ripening_lot_id',true) for update;
  end if;
  if fn in ('ripening_plan_register','ripening_plan_update') then
    y:=private.rpc_input_positive_int(input_value,'harvest_year',false);
    m:=private.rpc_input_positive_int(input_value,'harvest_month',false);
    if (y is null)<>(m is null) or y not between 2000 and 9999 or m not between 1 and 12 then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫年度と月を両方指定してください。');
    end if;
    y:=coalesce(y,previous.harvest_year); m:=coalesce(m,previous.harvest_month);
  elsif input_value ? 'harvest_year' or input_value ? 'harvest_month' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫年度・月は計画登録または変更時に指定してください。');
  end if;
  result:=private.ripening_plan_action_before_deadlines(fn,input_value-'harvest_year'-'harvest_month',actor,correlation);
  select * into lot from public.ripening_lots where id=(result->>'id')::uuid;
  if fn in ('ripening_plan_register','ripening_plan_update') and y is not null then
    if previous.harvest_year=y and previous.harvest_month=m and previous.variety_id=lot.variety_id
      and previous.master_snapshot ? 'best_before_days' then
      snap:=previous.master_snapshot;
    else
      select * into rule from public.ripening_rules where harvest_year=y and harvest_month=m
        and variety_id=lot.variety_id and is_active for share;
      if not found then
        perform private.rpc_fail('KW400','RIPENING_MASTER_NOT_FOUND','収穫年度・月・品種に一致する有効な追熟マスターがありません。');
      end if;
      snap:=to_jsonb(rule)-'created_by'-'updated_by'-'created_at'-'updated_at';
    end if;
    update public.ripening_lots set harvest_year=y,harvest_month=m,master_snapshot=snap,updated_by=actor where id=lot.id;
    perform private.project_ripening_tasks(lot.id,actor,'収穫年度別の追熟予定計算',correlation);
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
      select 'ripening_lot',l.id,'update',to_jsonb(lot),to_jsonb(l),'追熟条件の保存',actor,correlation
      from public.ripening_lots l where l.id=lot.id and to_jsonb(l)<>to_jsonb(lot);
  end if;
  return public.ripening_plan_get(lot.id);
end;
$$;

-- The original plan stays intact. Calculated dates may follow an actual injection.
alter function private.project_ripening_tasks(uuid,uuid,text,uuid) rename to project_ripening_tasks_before_deadlines;
create function private.project_ripening_tasks(lot_id uuid,actor uuid,reason_value text,correlation uuid)
returns void language plpgsql set search_path='' as $$
declare lot public.ripening_lots%rowtype; base_at timestamptz; dates record; t public.work_tasks%rowtype; at_value timestamptz;
begin
  select * into lot from public.ripening_lots where id=lot_id;
  if not (lot.master_snapshot ? 'best_before_days') then
    perform private.project_ripening_tasks_before_deadlines(lot_id,actor,reason_value,correlation); return;
  end if;
  select actual_at into base_at from public.ripening_work_results where ripening_lot_id=lot_id and work_type='ethylene_injection';
  select * into dates from private.calculate_ripening_dates(coalesce(base_at,lot.planned_ethylene_at),lot.master_snapshot);
  update public.ripening_lots set calculated_removal_at=dates.removal_at,calculated_rest_end_at=dates.rest_end_at,
    calculated_shippable_until=dates.shippable_until,calculated_best_before_at=dates.best_before_at where id=lot_id;
  -- Only plan mutations need to create/cancel tasks. After start keep actual locations.
  if base_at is null then
    perform private.project_ripening_tasks_before_deadlines(lot_id,actor,reason_value,correlation);
  end if;
  for t in select * from public.work_tasks where ripening_lot_id=lot_id and managed_by_planning
    and status='pending' and task_type in ('ethylene_removal_check','ripeness_check') order by id for update
  loop
    at_value:=case t.task_type when 'ethylene_removal_check' then dates.removal_at else dates.rest_end_at end;
    if row(t.scheduled_at,t.due_at,t.schedule_warning) is distinct from row(at_value,at_value,null::text) then
      update public.work_tasks set scheduled_at=at_value,due_at=at_value,schedule_warning=null,version=version+1,updated_by=actor where id=t.id;
      insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
        select 'work_task',w.id,'update',to_jsonb(t),to_jsonb(w),reason_value,actor,correlation from public.work_tasks w where w.id=t.id;
    end if;
  end loop;
  if base_at is not null then
    update public.containers set shippable_from=dates.rest_end_at,shippable_until=dates.shippable_until,
      best_before_at=dates.best_before_at,version=version+1,updated_by=actor
      where ripening_lot_id=lot_id and row(shippable_from,shippable_until,best_before_at)
        is distinct from row(dates.rest_end_at,dates.shippable_until,dates.best_before_at);
  end if;
end;
$$;

create function private.clear_completed_task_overdue() returns trigger language plpgsql set search_path='' as $$
begin
  if new.status<>'pending' then new.is_overdue:=false;
  elsif new.due_at is distinct from old.due_at or new.status is distinct from old.status then
    new.is_overdue:=new.due_at<=clock_timestamp();
  end if;
  return new;
end;
$$;
create trigger work_tasks_clear_overdue before update of status,due_at on public.work_tasks
for each row execute function private.clear_completed_task_overdue();

create function private.process_ripening_deadlines(at_value timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cutoff timestamptz; c public.containers%rowtype; t public.work_tasks%rowtype;
  row_before record; expired_count int:=0; overdue_count int:=0; correlation uuid:=gen_random_uuid();
begin
  perform pg_advisory_xact_lock(53,0);
  cutoff:=coalesce(at_value,clock_timestamp());
  if not isfinite(cutoff) then raise exception 'finite deadline time required'; end if;
  for t in select * from public.work_tasks where status='pending' and not is_overdue
    and due_at<=cutoff and task_type in ('ethylene_injection','ethylene_removal_check','ripeness_check','shipping')
    order by id for update
  loop
    update public.work_tasks set is_overdue=true,version=version+1 where id=t.id;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
      select 'work_task',w.id,'update',to_jsonb(t),to_jsonb(w),'期限超過（自動）',null,correlation from public.work_tasks w where w.id=t.id;
    overdue_count:=overdue_count+1;
  end loop;
  for c in select * from public.containers where ripening_lot_id is not null
    and current_weight_kg>0 and status<>'shipped'
    and ((best_before_at<=cutoff and status<>'expired') or (shippable_until<=cutoff and not needs_review)
      or (status='resting' and shippable_from<=cutoff)) order by id for update
  loop
    update public.containers set status=case when best_before_at<=cutoff then 'expired'
        when status='resting' and shippable_from<=cutoff then 'awaiting_ripeness_check' else status end,
      expired_at=case when best_before_at<=cutoff then coalesce(expired_at,cutoff) else expired_at end,
      needs_review=needs_review or shippable_until<=cutoff,version=version+1 where id=c.id;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
      select 'container',v.id,'transition',to_jsonb(c),to_jsonb(v),'追熟期限更新（自動）',null,correlation from public.containers v where v.id=c.id;
    if c.best_before_at<=cutoff and c.status<>'expired' then expired_count:=expired_count+1; end if;
    if c.shippable_until<=cutoff then
      for row_before in select id,to_jsonb(l) data from public.ripening_lots l where not needs_review
        and (id=c.ripening_lot_id or id in(select ripening_lot_id from public.inventory_reservations where container_id=c.id and status='active'))
        order by id for update
      loop
        update public.ripening_lots set needs_review=true,version=version+1 where id=row_before.id;
        insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
          select 'ripening_lot',l.id,'update',row_before.data,to_jsonb(l),'期限切れ在庫の要再確認（自動）',null,correlation
          from public.ripening_lots l where l.id=row_before.id;
      end loop;
      for row_before in select id,to_jsonb(r) data from public.inventory_reservations r where not needs_review
        and (ripening_lot_id=c.ripening_lot_id or container_id=c.id) and status<>'released' order by id for update
      loop
        update public.inventory_reservations set needs_review=true where id=row_before.id;
        insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
          select 'inventory_reservation',r.id,'update',row_before.data,to_jsonb(r),'期限切れ在庫の要再確認（自動）',null,correlation
          from public.inventory_reservations r where r.id=row_before.id;
      end loop;
      for row_before in select id,to_jsonb(o) data from public.orders o where not needs_review
        and id in(select order_id from public.ripening_allocations where ripening_lot_id=c.ripening_lot_id
          or ripening_lot_id in(select ripening_lot_id from public.inventory_reservations where container_id=c.id and status='active'))
        order by id for update
      loop
        update public.orders set needs_review=true,version=version+1 where id=row_before.id;
        insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
          select 'order',o.id,'update',row_before.data,to_jsonb(o),'期限切れ在庫の要再確認（自動）',null,correlation
          from public.orders o where o.id=row_before.id;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('expired',expired_count,'overdue',overdue_count);
end;
$$;
create function public.ripening_deadlines_process() returns jsonb language sql security definer set search_path='' as $$
  select private.process_ripening_deadlines();
$$;
revoke all on function public.ripening_deadlines_process() from public,anon,authenticated;
grant execute on function public.ripening_deadlines_process() to service_role;
select cron.schedule('ripening-deadlines','* * * * *','select private.process_ripening_deadlines()');

create or replace function private.validate_container_transition()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'awaiting_label' and new.status = 'cold_storage') or
      (old.status = 'cold_storage' and new.status = 'ethylene_processing') or
      (old.status = 'ethylene_processing' and new.status = 'resting') or
      (old.status = 'resting' and new.status = 'awaiting_ripeness_check') or
      (old.status = 'awaiting_ripeness_check' and new.status = 'shippable') or
      (old.status = 'shippable' and new.status in ('shipped', 'expired')) or
      (old.status in ('ethylene_processing','resting','awaiting_ripeness_check') and new.status='expired'
        and new.best_before_at is not null and new.expired_at>=new.best_before_at) or
      (old.status = 'shipped' and new.status in ('shippable', 'expired') and new.current_weight_kg > 0)
    ) then
      raise exception 'invalid container status transition' using errcode = '23514';
    end if;
    if new.status = 'cold_storage' and not exists (
      select 1 from public.label_jobs l where l.container_id = new.id
      and l.status in ('printed', 'handwritten')
    ) then
      raise exception 'label completion is required' using errcode = '23514';
    end if;
    if new.status = 'shipped' and new.current_weight_kg <> 0 then
      raise exception 'shipped container must be empty' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.ripening_work_action(fn text, input_value jsonb, actor uuid,
  correlation uuid, operation uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare
  kind text;
  lot_id uuid;
  expected bigint;
  location_value uuid;
  worker_value uuid;
  actual_value timestamptz;
  temperature_value numeric;
  resting_value timestamptz;
  rest_temperature_value numeric;
  notes_value text;
  lot public.ripening_lots%rowtype;
  source public.containers%rowtype;
  reservation public.inventory_reservations%rowtype;
  target public.containers%rowtype;
  task public.work_tasks%rowtype;
  downstream_task public.work_tasks%rowtype;
  location_name text;
  previous_result public.ripening_work_results%rowtype;
  order_ids uuid[];
  source_ids uuid[];
  before_value jsonb;
  after_value jsonb;
  old_row jsonb;
  new_row jsonb;
  entry record;
  task_before jsonb;
  output_id uuid;
  label_row public.label_jobs%rowtype;
begin
  kind := case fn
    when 'ripening_ethylene_injection_complete' then 'ethylene_injection'
    when 'ripening_ethylene_removal_complete' then 'ethylene_removal_check'
    when 'ripening_ripeness_complete' then 'ripeness_check'
    else null end;
  if kind is null then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','未対応の作業です。');
  end if;
  perform private.customer_order_validate_keys(input_value,
    array['ripening_lot_id','expected_version','actual_at','actual_temperature',
      'location_id','performed_by','checked','notes'] ||
    case when kind='ethylene_removal_check' then array['rest_started_at','rest_temperature']
      else array[]::text[] end);
  lot_id := private.rpc_input_uuid(input_value,'ripening_lot_id',true);
  expected := private.rpc_input_positive_int(input_value,'expected_version',true);
  location_value := private.rpc_input_uuid(input_value,'location_id',true);
  worker_value := private.rpc_input_uuid(input_value,'performed_by',true);
  notes_value := private.rpc_input_text(input_value,'notes',false);
  if input_value->'checked' is distinct from 'true'::jsonb then
    perform private.rpc_fail('KW400','CONFIRMATION_REQUIRED','対象と作業の実施確認が必要です。');
  end if;
  actual_value := case when not (input_value ? 'actual_at') then statement_timestamp()
    else private.ripening_timestamp(input_value,'actual_at') end;
  temperature_value := private.ripening_work_temperature(input_value,'actual_temperature');
  if kind='ethylene_removal_check' then
    resting_value := case when not (input_value ? 'rest_started_at') then actual_value
      else private.ripening_timestamp(input_value,'rest_started_at') end;
    rest_temperature_value := private.ripening_work_temperature(input_value,'rest_temperature');
    if resting_value < actual_value then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','寝かせ開始は抜き確認以降にしてください。');
    end if;
  end if;
  -- Same lock as S2 planning/order mutations: preserve confirmed allocations.
  perform pg_advisory_xact_lock(53,0);
  select * into lot from public.ripening_lots where id=lot_id for update;
  if not found then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟計画が見つかりません。');
  end if;
  if lot.version<>expected then
    perform private.rpc_fail('KW409','CONFLICT_STALE','最新の追熟計画を読み直してください。',
      jsonb_build_object('current_version',lot.version));
  end if;
  if (kind='ethylene_injection' and lot.status<>'confirmed')
    or (kind<>'ethylene_injection' and lot.status<>'in_progress')
    or exists(select 1 from public.ripening_work_results r
      where r.ripening_lot_id=lot_id and r.work_type=kind) then
    perform private.rpc_fail('KW409','INVALID_WORK_STATE','この工程は実行できないか完了済みです。');
  end if;
  if not exists(select 1 from public.workers where id=worker_value and is_active for share)
    or not exists(select 1 from public.storage_locations where id=location_value and is_active for share) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','担当者または場所が無効です。');
  end if;
  select * into task from public.work_tasks
    where ripening_lot_id=lot_id and task_type=kind and managed_by_planning for update;
  if not found or task.status<>'pending' then
    perform private.rpc_fail('KW409','INVALID_WORK_STATE','対象作業が見つからないか完了済みです。');
  end if;
  task_before := to_jsonb(task);
  select coalesce(array_agg(distinct order_id order by order_id),array[]::uuid[]) into order_ids
    from public.ripening_allocations where ripening_lot_id=lot_id and order_id is not null;
  select coalesce(array_agg(container_id order by container_id),array[]::uuid[]) into source_ids
    from public.inventory_reservations where ripening_lot_id=lot_id;
  perform 1 from public.orders where id=any(order_ids) order by id for update;
  perform 1 from public.containers where id=any(source_ids) or ripening_lot_id=lot_id
    order by id for update;
  before_value := private.ripening_audit_snapshot(lot_id,order_ids,array[]::uuid[]);
  -- Label guard: all ripening container labels must be handled before removal.
  if kind='ethylene_removal_check' and exists(
    select 1 from public.label_jobs j
    join public.containers c on c.id=j.container_id
    where c.ripening_lot_id=lot_id
      and j.status not in ('printed','handwritten')
  ) then
    perform private.rpc_fail('KW400','LABEL_REQUIRED',
      '追熟ラベルの印刷または手書き対応を先に完了してください。');
  end if;

  if kind='ethylene_injection' then
    if not (lot.master_snapshot ? 'best_before_days') or lot.harvest_year is null then
      perform private.rpc_fail('KW400','RIPENING_MASTER_NOT_FOUND','収穫年度・月に対応する追熟マスターを計画に設定してください。');
    end if;
    if lot.needs_review or lot.allocated_weight_kg<>lot.total_weight_kg
      or (select coalesce(sum(allocated_weight_kg),0) from public.ripening_allocations
        where ripening_lot_id=lot_id)<>lot.total_weight_kg
      or (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
        where ripening_lot_id=lot_id and status='active')<>lot.total_weight_kg then
      perform private.rpc_fail('KW400','RIPENING_WEIGHT_MISMATCH','内訳と予約を再確認してください。');
    end if;
    if exists(select 1 from public.orders o where o.id=any(order_ids)
      and (o.status not in ('confirmed','in_progress','partially_shipped')
        or o.variety_id<>lot.variety_id or o.grade_id<>lot.grade_id)) then
      perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','割当受注を再確認してください。');
    end if;
    if exists(select 1 from public.containers where ripening_lot_id=lot_id) then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','追熟コンテナは作成済みです。');
    end if;
    for reservation in select * from public.inventory_reservations
      where ripening_lot_id=lot_id and status='active' order by container_id
    loop
      select * into source from public.containers where id=reservation.container_id;
      if source.status<>'cold_storage' or source.variety_id<>lot.variety_id
        or source.grade_id<>lot.grade_id or source.current_weight_kg<source.reserved_weight_kg then
        perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','予約元在庫を再確認してください。');
      end if;
      update public.inventory_reservations set status='consumed',consumed_at=actual_value,updated_by=actor
        where id=reservation.id;
      insert into public.inventory_events (
        container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
        ripening_lot_id,operation_id,occurred_at,reason,created_by
      ) values(source.id,'ripening_out',-reservation.reserved_weight_kg,source.current_weight_kg,
        source.current_weight_kg-reservation.reserved_weight_kg,lot_id,operation,actual_value,'追熟注入開始',actor);
    end loop;
    output_id := gen_random_uuid();
    insert into public.containers (
      id,display_id,ripening_lot_id,variety_id,grade_id,original_weight_kg,current_weight_kg,
      status,location_id,created_by,updated_by
    ) values(output_id,lot.display_id||'-1',lot_id,lot.variety_id,lot.grade_id,
      lot.total_weight_kg,0,'ethylene_processing',location_value,actor,actor);
    insert into public.inventory_events (
      container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
      ripening_lot_id,operation_id,occurred_at,reason,created_by
    ) values(output_id,'ripening_in',lot.total_weight_kg,0,lot.total_weight_kg,
      lot_id,operation,actual_value,'追熟コンテナ生成',actor);
    -- Create the ripening label job so the field team can print before removal.
    insert into public.label_jobs(container_id,created_by,updated_by)
      values(output_id,actor,actor)
      returning * into label_row;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values('label_job',label_row.id,'create',null,to_jsonb(label_row),'追熟注入完了',actor,correlation);
    update public.orders set status='in_progress',version=version+1,updated_by=actor
      where id=any(order_ids) and status='confirmed';
    update public.ripening_lots set status='in_progress',version=version+1,updated_by=actor
      where id=lot_id;
  else
    select * into previous_result from public.ripening_work_results r
      where r.ripening_lot_id=lot_id and r.work_type=
        case when kind='ethylene_removal_check' then 'ethylene_injection' else 'ethylene_removal_check' end;
    if not found then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','前工程を完了してください。');
    end if;
    if actual_value < coalesce(previous_result.rest_started_at,previous_result.actual_at) then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','実績日時は前工程以降を指定してください。');
    end if;
    if not exists(select 1 from public.containers where ripening_lot_id=lot_id)
      or exists(select 1 from public.containers where ripening_lot_id=lot_id and
        ((kind='ethylene_removal_check' and status<>'ethylene_processing') or
         (kind='ripeness_check' and status not in ('resting','awaiting_ripeness_check')))) then
      perform private.rpc_fail('KW409','INVALID_WORK_STATE','現物工程を再確認してください。');
    end if;
    for target in select * from public.containers where ripening_lot_id=lot_id order by id loop
      if kind='ripeness_check' and target.status='resting' then
        update public.containers set status='awaiting_ripeness_check' where id=target.id;
      end if;
      update public.containers set status=case when kind='ethylene_removal_check'
          then 'resting' else 'shippable' end,
        location_id=location_value,version=version+1,updated_by=actor where id=target.id;
      insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
        reason,changed_by,correlation_id)
      select 'container',target.id,'transition',to_jsonb(target),to_jsonb(c),kind,actor,correlation
        from public.containers c where id=target.id;
    end loop;
    update public.ripening_lots set status=case when kind='ripeness_check' then 'completed' else status end,
      version=version+1,updated_by=actor where id=lot_id;
  end if;
  insert into public.ripening_work_results (
    ripening_lot_id,work_type,actual_at,actual_temperature,location_id,performed_by,
    checked,rest_started_at,rest_temperature,notes,operation_id,created_by
  ) values(lot_id,kind,actual_value,temperature_value,location_value,worker_value,
    true,resting_value,rest_temperature_value,notes_value,operation,actor);
  update public.work_tasks set status='completed',completed_at=actual_value,completed_by=worker_value,
    notes=notes_value,version=version+1,updated_by=actor where id=task.id;
  insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
    reason,changed_by,correlation_id)
  select 'work_task',task.id,'transition',task_before,to_jsonb(t),kind,actor,correlation
    from public.work_tasks t where id=task.id;
  -- Actual placement is the next worker's destination, without replanning dates.
  select name into location_name from public.storage_locations where id=location_value;
  for downstream_task in
    select * from public.work_tasks
    where ripening_lot_id=lot_id and managed_by_planning and status='pending'
      and ((kind='ethylene_injection' and task_type in ('ethylene_removal_check','ripeness_check'))
        or (kind='ethylene_removal_check' and task_type='ripeness_check'))
      and task_details->>'location' is distinct from location_name
    order by id for update
  loop
    update public.work_tasks
      set task_details=jsonb_set(task_details,'{location}',to_jsonb(location_name),true),
        version=version+1,updated_by=actor
      where id=downstream_task.id;
    -- Updating task_details also queues the new calendar revision.
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    select 'work_task',t.id,'update',to_jsonb(downstream_task),to_jsonb(t),
      kind,actor,correlation from public.work_tasks t where t.id=downstream_task.id;
  end loop;
  perform private.project_ripening_tasks(lot_id,actor,'注入実績基準の追熟予定計算',correlation);
  after_value := private.ripening_audit_snapshot(lot_id,order_ids,array[]::uuid[]);
  for entry in select key from jsonb_object_keys(before_value||after_value) key loop
    old_row := before_value->entry.key; new_row := after_value->entry.key;
    if old_row is not distinct from new_row then continue; end if;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values(new_row->>'entity',(new_row->>'id')::uuid,'update',old_row->'data',new_row->'data',kind,actor,correlation);
  end loop;
  perform private.process_ripening_deadlines();
  return public.ripening_work_get(lot_id);
end;
$$;

create or replace function private.shipment_action(fn text,input_value jsonb,actor uuid,correlation uuid,operation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.orders%rowtype; s public.shipments%rowtype; c public.containers%rowtype;
 elem jsonb; line public.shipment_lines%rowtype; event public.inventory_events%rowtype;
 target uuid; worker uuid; at_value timestamptz; expected bigint; amount numeric; total numeric:=0;
 lines_value jsonb; normalized_lines jsonb:='[]'::jsonb; seen uuid[]:=array[]::uuid[]; lot_id uuid; lot_amount numeric; allocated numeric;
 reason_value text; notes_value text; cust jsonb;
begin
 perform pg_advisory_xact_lock(53,0);
 reason_value:=private.rpc_input_text(input_value,'reason',true);
 if fn='shipment_confirm' then
   perform private.customer_order_validate_keys(input_value,array['order_id','expected_order_version','shipped_at','worker_id','checked','lines','notes','reason']);
   target:=private.rpc_input_uuid(input_value,'order_id',true);
   expected:=private.rpc_input_positive_int(input_value,'expected_order_version',true);
   worker:=private.rpc_input_uuid(input_value,'worker_id',true);
   notes_value:=private.rpc_input_text(input_value,'notes',false);
   if input_value->'checked' is distinct from 'true'::jsonb then
     perform private.rpc_fail('KW400','CONFIRMATION_REQUIRED','出荷内容の確認が必要です。',jsonb_build_object('field','checked'));
   end if;
   at_value:=case when not(input_value ? 'shipped_at') then statement_timestamp()
     else private.ripening_timestamp(input_value,'shipped_at') end;
   if at_value is null or not isfinite(at_value) or at_value>statement_timestamp() then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷日時は現在以前を指定してください。',jsonb_build_object('field','shipped_at'));
   end if;
   if not exists(select 1 from public.workers where id=worker and is_active) then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','有効な作業者を指定してください。',jsonb_build_object('field','worker_id'));
   end if;
   select * into o from public.orders where id=target for update;
   if not found or o.status not in ('confirmed','in_progress','partially_shipped') then
     perform private.rpc_fail('KW409','ORDER_UNAVAILABLE','この受注は出荷できません。',null);
   end if;
   if o.version<>expected then
     perform private.rpc_fail('KW409','CONFLICT_STALE','受注が更新されています。再読込してください。',jsonb_build_object('version',o.version));
   end if;
   lines_value:=input_value->'lines';
   if jsonb_typeof(lines_value) is distinct from 'array' then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷明細を指定してください。',jsonb_build_object('field','lines'));
   end if;
   if jsonb_array_length(lines_value) not between 1 and 100 then
     perform private.rpc_fail('KW400','VALIDATION_FAILED','明細は1〜100件で指定してください。',null);
   end if;
   for elem in select value from jsonb_array_elements(lines_value) loop
     if jsonb_typeof(elem) is distinct from 'object' then
       perform private.rpc_fail('KW400','VALIDATION_FAILED','明細はオブジェクトで指定してください。',jsonb_build_object('field','lines'));
     end if;
     perform private.customer_order_validate_keys(elem,array['container_id','expected_version','shipped_weight_kg']);
     target:=private.rpc_input_uuid(elem,'container_id',true);
     expected:=private.rpc_input_positive_int(elem,'expected_version',true);
     amount:=private.rpc_input_weight(elem,'shipped_weight_kg',true,false);
     if target=any(seen) then
       perform private.rpc_fail('KW400','VALIDATION_FAILED','同じコンテナを重複指定できません。',null);
     end if;
     seen:=array_append(seen,target); total:=total+amount;
     normalized_lines:=normalized_lines||jsonb_build_array(jsonb_build_object('container_id',target,'expected_version',expected,'shipped_weight_kg',amount));
   end loop;
   lines_value:=normalized_lines;
   if total>o.ordered_weight_kg-private.shipped_weight(o.id) then
     perform private.rpc_fail('KW400','ORDER_WEIGHT_EXCEEDED','受注の未出荷量を超えています。',null);
   end if;
   -- Stable lock order; the planning advisory lock also serializes allocation changes.
   perform 1 from public.containers where id=any(seen) order by id for update;
   for elem in select value from jsonb_array_elements(lines_value) loop
     select * into c from public.containers where id=(elem->>'container_id')::uuid;
     if not found or c.ripening_lot_id is null or row(c.variety_id,c.grade_id) is distinct from row(o.variety_id,o.grade_id) then
       perform private.rpc_fail('KW400','CONTAINER_UNAVAILABLE','対象の追熟コンテナを指定してください。',null);
     end if;
     if c.version<>(elem->>'expected_version')::bigint then
       perform private.rpc_fail('KW409','CONFLICT_STALE','コンテナが更新されています。再読込してください。',jsonb_build_object('container_id',c.id,'version',c.version));
     end if;
     if c.best_before_at is null or c.shippable_until is null then
       perform private.rpc_fail('KW400','DEADLINE_UNSET','出荷期限が設定されていません。',null);
     end if;
     if least(c.best_before_at,c.shippable_until)<=greatest(clock_timestamp(),at_value) or c.status='expired' then
       perform private.rpc_fail('KW400','CONTAINER_EXPIRED','出荷期限を過ぎています。',null);
     end if;
     if c.shippable_from is not null and (clock_timestamp()<c.shippable_from or at_value<c.shippable_from) then
       perform private.rpc_fail('KW400','CONTAINER_UNAVAILABLE','出荷可能期間が始まっていません。',null);
     end if;
     if c.status<>'shippable' then
       perform private.rpc_fail('KW400','CONTAINER_UNAVAILABLE','出荷可能なコンテナではありません。',null);
     end if;
     if (elem->>'shipped_weight_kg')::numeric>c.current_weight_kg-c.reserved_weight_kg then
       perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','コンテナの使用可能残量を超えています。',null);
     end if;
   end loop;
   for lot_id in select distinct ripening_lot_id from public.containers where id=any(seen) loop
     select sum((e.value->>'shipped_weight_kg')::numeric) into lot_amount
       from jsonb_array_elements(lines_value) e join public.containers cc on cc.id=(e.value->>'container_id')::uuid
       where cc.ripening_lot_id=lot_id;
     select allocated_weight_kg into allocated from public.ripening_allocations where ripening_lot_id=lot_id and order_id=o.id;
     if allocated is null or lot_amount>allocated-private.shipped_weight(o.id,lot_id) then
       perform private.rpc_fail('KW400','ALLOCATION_UNAVAILABLE','この受注に割り当てられた残量を超えています。',null);
     end if;
   end loop;
   select jsonb_build_object('customer_id',id,'customer_code',customer_code,'name',name,'nickname',nickname)
     into cust from public.customers where id=o.customer_id;
   insert into public.shipments(display_id,order_id,shipped_at,shipped_by,customer_snapshot,shipping_destination_snapshot,
     operation_id,correlation_id,reason,notes,created_by,updated_by)
   values(private.next_display_id('出荷',extract(year from at_value at time zone 'Asia/Tokyo')::integer),o.id,at_value,worker,
     cust,o.shipping_destination_snapshot,operation,correlation,reason_value,notes_value,actor,actor) returning * into s;
   for elem in select value from jsonb_array_elements(lines_value) order by value->>'container_id' loop
     select * into strict c from public.containers where id=(elem->>'container_id')::uuid;
     amount:=(elem->>'shipped_weight_kg')::numeric;
     insert into public.shipment_lines(shipment_id,container_id,shipped_weight_kg,created_by)
       values(s.id,c.id,amount,actor) returning * into line;
     insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
       shipment_line_id,operation_id,correlation_id,occurred_at,reason,created_by)
       values(c.id,'shipment',-amount,c.current_weight_kg,c.current_weight_kg-amount,line.id,operation,correlation,at_value,reason_value,actor);
   end loop;
 elsif fn='shipment_cancel' then
   perform private.customer_order_validate_keys(input_value,array['shipment_id','expected_version','reason']);
   target:=private.rpc_input_uuid(input_value,'shipment_id',true);
   expected:=private.rpc_input_positive_int(input_value,'expected_version',true);
   select * into s from public.shipments where id=target for update;
   if not found or s.status<>'confirmed' then
     perform private.rpc_fail('KW409','SHIPMENT_UNAVAILABLE','この出荷は取消できません。',null);
   end if;
   if s.version<>expected then
     perform private.rpc_fail('KW409','CONFLICT_STALE','出荷が更新されています。',jsonb_build_object('version',s.version));
   end if;
   select * into strict o from public.orders where id=s.order_id for update;
   if o.status='cancelled' then
     perform private.rpc_fail('KW409','ORDER_UNAVAILABLE','キャンセル済み受注の出荷は取消できません。',null);
   end if;
   perform 1 from public.containers c2 where id in (select container_id from public.shipment_lines where shipment_id=s.id) order by id for update;
   for line in select * from public.shipment_lines where shipment_id=s.id order by container_id loop
     select * into strict c from public.containers where id=line.container_id;
     if c.current_weight_kg+line.shipped_weight_kg>c.original_weight_kg then
       perform private.rpc_fail('KW409','INVENTORY_CONFLICT','取消後の重量が元の重量を超えます。確認してください。',null);
     end if;
   end loop;
   update public.shipments set status='cancelled',cancelled_at=greatest(statement_timestamp(),shipped_at),cancelled_by=actor,
     cancellation_reason=reason_value,cancellation_operation_id=operation,correlation_id=correlation,version=version+1,updated_by=actor where id=s.id;
   for line in select * from public.shipment_lines where shipment_id=s.id order by container_id loop
     select * into strict c from public.containers where id=line.container_id;
     select * into strict event from public.inventory_events where shipment_line_id=line.id and event_type='shipment';
     insert into public.inventory_events(container_id,event_type,quantity_delta_kg,before_weight_kg,after_weight_kg,
       shipment_line_id,reverses_event_id,operation_id,correlation_id,occurred_at,reason,created_by)
     values(c.id,'shipment_cancel',line.shipped_weight_kg,c.current_weight_kg,c.current_weight_kg+line.shipped_weight_kg,
       line.id,event.id,operation,correlation,greatest(statement_timestamp(),event.occurred_at),reason_value,actor);
   end loop;
 else raise exception 'unsupported shipment operation'; end if;
 perform private.refresh_shipped_order(o.id,actor,correlation,reason_value,s.shipped_by);
 return public.shipment_get(s.id)||jsonb_build_object('order',public.order_get(o.id));
end;
$$;
revoke all on function private.master_table(text) from public,anon,authenticated;
revoke all on function private.master_validate(text,text,jsonb,jsonb) from public,anon,authenticated;
revoke all on function private.master_check_duplicates(text,jsonb,uuid) from public,anon,authenticated;
revoke all on function private.master_guard_parents_active(text,jsonb) from public,anon,authenticated;
revoke all on function private.master_guard_dependents(text,uuid) from public,anon,authenticated;
revoke all on function private.calculate_ripening_dates(timestamptz,jsonb) from public,anon,authenticated;
revoke all on function private.ripening_plan_action(text,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function private.project_ripening_tasks(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.clear_completed_task_overdue() from public,anon,authenticated;
revoke all on function private.process_ripening_deadlines(timestamptz) from public,anon,authenticated;
create or replace function public.shipment_container_list(order_id_value uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
 'remaining_use_type',private.remaining_lot_use(c.ripening_lot_id),
 'available_weight_kg',greatest(0,least(c.current_weight_kg-c.reserved_weight_kg,
 a.allocated_weight_kg-private.shipped_weight(o.id,c.ripening_lot_id),
 o.ordered_weight_kg-private.shipped_weight(o.id)))) order by c.display_id,c.id),'[]'::jsonb)
 from public.containers c join public.ripening_allocations a on a.ripening_lot_id=c.ripening_lot_id
 join public.orders o on o.id=a.order_id
 where private.current_user_is_active() and o.id=order_id_value
 and o.status in ('confirmed','in_progress','partially_shipped')
 and (c.shippable_from is null or c.shippable_from<=statement_timestamp())
 and c.status='shippable' and c.current_weight_kg>c.reserved_weight_kg
 and least(c.shippable_until,c.best_before_at)>statement_timestamp()
 and c.shippable_until is not null and c.best_before_at is not null;
$$;
commit;
