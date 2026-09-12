begin;

create table private.work_task_settings (
  singleton boolean primary key default true check (singleton),
  ethylene_processing_hours numeric not null check (ethylene_processing_hours > 0 and ethylene_processing_hours <= 720)
);
-- Farm default confirmed for Issue #57: one week.
insert into private.work_task_settings(singleton,ethylene_processing_hours) values(true,168);
revoke all on private.work_task_settings from public,anon,authenticated;
grant select,update on private.work_task_settings to service_role;

alter table public.work_tasks
  add column managed_by_planning boolean not null default false,
  add column task_details jsonb not null default '{}'::jsonb check (jsonb_typeof(task_details)='object'),
  add column schedule_warning text;
create unique index work_tasks_planned_lot_type_key
  on public.work_tasks(ripening_lot_id,task_type) where managed_by_planning and ripening_lot_id is not null;
create unique index work_tasks_planned_order_type_key
  on public.work_tasks(order_id,task_type) where managed_by_planning and order_id is not null;

-- A pending retry retains its stable event ID. Existing unnamed checks are
-- discovered by their definition, rather than relying on generated numbering.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
    where conrelid='public.work_tasks'::regclass and contype='c'
      and pg_get_constraintdef(oid) like '%calendar_sync_status%'
      and pg_get_constraintdef(oid) like '%calendar_event_id%'
  loop
    execute format('alter table public.work_tasks drop constraint %I',c.conname);
  end loop;
end;
$$;
alter table public.work_tasks add constraint work_tasks_calendar_sync_state_check check (
  (calendar_sync_status='synced' and nullif(btrim(calendar_event_id),'') is not null and calendar_sync_error is null)
  or (calendar_sync_status='failed' and nullif(btrim(calendar_sync_error),'') is not null)
  or (calendar_sync_status in ('pending','not_required') and calendar_sync_error is null)
);

create table private.calendar_sync_jobs (
  task_id uuid primary key references public.work_tasks(id) on delete cascade,
  revision bigint not null,
  event_generation integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  attempts integer not null default 0,
  lease_token uuid,
  lease_until timestamptz,
  check ((lease_token is null)=(lease_until is null))
);
create index calendar_sync_jobs_due_idx on private.calendar_sync_jobs(next_attempt_at);
create table private.calendar_sync_log (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.work_tasks(id) on delete restrict,
  revision bigint not null,
  outcome text not null check (outcome in ('synced','failed','stale')),
  error_code text,
  attempted_at timestamptz not null default now()
);
revoke all on private.calendar_sync_jobs,private.calendar_sync_log from public,anon,authenticated;
grant select on private.calendar_sync_jobs,private.calendar_sync_log to service_role;

create function private.enqueue_calendar_task()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not new.managed_by_planning then return new; end if;
  if tg_op='UPDATE' and new.version<=old.version then
    new.version := old.version+1;
  end if;
  new.calendar_event_id := coalesce(new.calendar_event_id,'task'||replace(new.id::text,'-','')||'g0');
  new.calendar_sync_status := 'pending';
  new.calendar_sync_error := null;
  return new;
end;
$$;
create trigger work_tasks_calendar_prepare before insert or update of
  status,scheduled_at,due_at,task_details,target_url,assigned_worker_id,schedule_warning on public.work_tasks
for each row execute function private.enqueue_calendar_task();

create function private.queue_calendar_task()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not new.managed_by_planning then return null; end if;
  insert into private.calendar_sync_jobs(task_id,revision) values(new.id,new.version)
  on conflict(task_id) do update set revision=excluded.revision,next_attempt_at=now(),attempts=0;
  -- Preserve an outstanding lease: a later acknowledgement will notice that
  -- its revision is stale and make the newest task immediately eligible.
  return null;
end;
$$;
create trigger work_tasks_calendar_queue after insert or update of
  status,scheduled_at,due_at,task_details,target_url,assigned_worker_id,schedule_warning on public.work_tasks
for each row execute function private.queue_calendar_task();

create function private.save_planned_task(
  kind text, target uuid, is_order boolean, source_active boolean,
  scheduled timestamptz, due timestamptz, worker uuid, details jsonb, warning text,
  actor uuid, reason_value text, correlation uuid
)
returns void language plpgsql set search_path = '' as $$
declare old_task public.work_tasks%rowtype; new_task public.work_tasks%rowtype; new_status text; task_id uuid;
begin
  select * into old_task from public.work_tasks
    where managed_by_planning and task_type=kind
      and ((is_order and order_id=target) or (not is_order and ripening_lot_id=target))
    for update;
  if not found and not source_active then return; end if;
  new_status := case when not source_active then 'cancelled'
    when old_task.status='completed' then 'completed' else 'pending' end;
  if old_task.id is null then
    task_id := gen_random_uuid();
    insert into public.work_tasks(id,task_type,ripening_lot_id,order_id,scheduled_at,due_at,
      assigned_worker_id,status,target_url,managed_by_planning,task_details,schedule_warning,created_by,updated_by)
    values(task_id,kind,case when not is_order then target end,case when is_order then target end,
      scheduled,due,worker,new_status,'/work-tasks/'||task_id,true,details,warning,actor,actor)
    returning * into new_task;
  else
    if row(old_task.status,old_task.scheduled_at,old_task.due_at,old_task.assigned_worker_id,old_task.task_details,old_task.schedule_warning)
      is not distinct from row(new_status,scheduled,due,worker,details,warning) then return; end if;
    update public.work_tasks set status=new_status,scheduled_at=scheduled,due_at=due,
      assigned_worker_id=worker,task_details=details,schedule_warning=warning,
      completed_at=case when new_status='completed' then old_task.completed_at end,
      completed_by=case when new_status='completed' then old_task.completed_by end,
      version=version+1,updated_by=actor where id=old_task.id returning * into new_task;
  end if;
  insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
  values('work_task',new_task.id,case when old_task.id is null then 'create'
    when old_task.status<>new_task.status then 'transition' else 'update' end,
    case when old_task.id is not null then to_jsonb(old_task) end,to_jsonb(new_task),
    reason_value,actor,correlation);
end;
$$;

create function private.project_ripening_tasks(lot_id uuid,actor uuid,reason_value text,correlation uuid)
returns void language plpgsql set search_path = '' as $$
declare lot public.ripening_lots%rowtype; details jsonb; removal_at timestamptz; hours_value numeric;
begin
  select * into lot from public.ripening_lots where id=lot_id;
  if not found then return; end if;
  select ethylene_processing_hours into hours_value from private.work_task_settings where singleton;
  hours_value := coalesce((lot.master_snapshot->>'task_ethylene_processing_hours')::numeric,hours_value);
  removal_at := lot.planned_ethylene_at + hours_value * interval '1 hour';
  select jsonb_build_object('variety',v.name,'grade',g.code,'weight_kg',lot.total_weight_kg,'location',s.name)
    into details from public.varieties v,public.grades g,public.storage_locations s
    where v.id=lot.variety_id and g.id=lot.grade_id and s.id=lot.storage_location_id;
  perform private.save_planned_task('ethylene_injection',lot.id,false,lot.status in ('confirmed','in_progress','completed'),
    lot.planned_ethylene_at,lot.planned_ethylene_at,lot.assigned_worker_id,details,null,actor,reason_value,correlation);
  perform private.save_planned_task('ethylene_removal_check',lot.id,false,lot.status in ('confirmed','in_progress','completed'),
    removal_at,removal_at,lot.assigned_worker_id,details,
    case when removal_at>lot.planned_completion_at then 'COMPLETION_BEFORE_REMOVAL' end,actor,reason_value,correlation);
  perform private.save_planned_task('ripeness_check',lot.id,false,lot.status in ('confirmed','in_progress','completed'),
    lot.planned_completion_at,lot.planned_completion_at,lot.assigned_worker_id,details,
    case when removal_at>lot.planned_completion_at then 'COMPLETION_BEFORE_REMOVAL' end,actor,reason_value,correlation);
end;
$$;

create function private.project_shipping_task(order_id_value uuid,actor uuid,reason_value text,correlation uuid)
returns void language plpgsql set search_path = '' as $$
declare o public.orders%rowtype; details jsonb; scheduled timestamptz;
begin
  select * into o from public.orders where id=order_id_value;
  if not found then return; end if;
  scheduled := o.scheduled_ship_on::timestamp at time zone 'Asia/Tokyo';
  select jsonb_build_object('variety',v.name,'grade',g.code,'weight_kg',o.ordered_weight_kg,
    'shipping_date',o.scheduled_ship_on) into details from public.varieties v,public.grades g
    where v.id=o.variety_id and g.id=o.grade_id;
  perform private.save_planned_task('shipping',o.id,true,o.status not in ('draft','cancelled'),
    scheduled,scheduled+interval '1 day'-interval '1 second',null,details,null,actor,reason_value,correlation);
end;
$$;

create function private.snapshot_task_processing_hours()
returns trigger language plpgsql set search_path = '' as $$
declare hours_value numeric;
begin
  if new.status='confirmed' and old.status<>'confirmed'
    and not (new.master_snapshot ? 'task_ethylene_processing_hours') then
    select ethylene_processing_hours into hours_value from private.work_task_settings where singleton;
    new.master_snapshot := new.master_snapshot||jsonb_build_object('task_ethylene_processing_hours',hours_value);
  end if;
  return new;
end;
$$;
create trigger ripening_lots_task_schedule before update of status on public.ripening_lots
for each row execute function private.snapshot_task_processing_hours();
revoke all on function private.snapshot_task_processing_hours() from public,anon,authenticated;

-- Wrap the existing actions, preserving their envelope, idempotency and lock.
alter function private.ripening_plan_action(text,jsonb,uuid,uuid) rename to ripening_plan_action_without_tasks;
create function private.ripening_plan_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result_value jsonb; lot_id uuid;
begin
  result_value := private.ripening_plan_action_without_tasks(fn,input_value,actor,correlation);
  lot_id := (result_value->>'id')::uuid;
  perform private.project_ripening_tasks(lot_id,actor,coalesce(nullif(btrim(input_value->>'reason'),''),'追熟計画登録'),correlation);
  return public.ripening_plan_get(lot_id);
end;
$$;

create or replace function private.customer_order_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result_value jsonb; plan_ids uuid[]; lot_id uuid;
begin
  perform pg_advisory_xact_lock(53,0);
  if fn in ('order_update','order_cancel') then
    select array_agg(distinct ripening_lot_id) into plan_ids
      from public.ripening_allocations where order_id=private.rpc_input_uuid(input_value,'order_id',true);
  end if;
  result_value := private.customer_order_action_without_planning_lock(fn,input_value,actor,correlation);
  if fn in ('order_register','order_update','order_confirm','order_cancel') then
    perform private.project_shipping_task((result_value->>'id')::uuid,actor,
      coalesce(nullif(btrim(input_value->>'reason'),''),'受注登録'),correlation);
    foreach lot_id in array coalesce(plan_ids,array[]::uuid[]) loop
      perform private.project_ripening_tasks(lot_id,actor,input_value->>'reason',correlation);
    end loop;
  end if;
  return result_value;
end;
$$;

create function public.calendar_sync_claim(batch_size integer default 5)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare job record; result_value jsonb:='[]'::jsonb; token uuid; task_value jsonb;
begin
  if batch_size is null or batch_size not between 1 and 5 then raise exception 'batch_size must be 1..5'; end if;
  for job in select j.* from private.calendar_sync_jobs j join public.work_tasks t on t.id=j.task_id
    where j.next_attempt_at<=now() and (j.lease_until is null or j.lease_until<now())
    order by case t.calendar_sync_status when 'pending' then 0 when 'failed' then 1 else 2 end,j.next_attempt_at,j.task_id
    limit batch_size for update of j skip locked
  loop
    token:=gen_random_uuid();
    update private.calendar_sync_jobs set lease_token=token,lease_until=now()+interval '5 minutes',attempts=attempts+1
      where task_id=job.task_id;
    select jsonb_build_object('id',t.id,'task_type',t.task_type,'status',t.status,'scheduled_at',t.scheduled_at,
      'due_at',t.due_at,'target_url',t.target_url,'version',t.version,'calendar_event_id',t.calendar_event_id,
      'task_details',t.task_details) into task_value from public.work_tasks t where t.id=job.task_id;
    result_value:=result_value||jsonb_build_array(jsonb_build_object('task',task_value,'lease_token',token,'revision',job.revision));
  end loop;
  return result_value;
end;
$$;

create function public.calendar_sync_finish(
  task_id_value uuid,lease_token_value uuid,revision_value bigint,error_code_value text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare job private.calendar_sync_jobs%rowtype; task_row public.work_tasks%rowtype; error_value text;
begin
  -- Same lock order as projection: task first, then its outbox row.
  select * into task_row from public.work_tasks where id=task_id_value for update;
  select * into job from private.calendar_sync_jobs where task_id=task_id_value for update;
  if not found or job.lease_token is distinct from lease_token_value or lease_token_value is null then return false; end if;
  if job.revision<>revision_value or task_row.version<>revision_value then
    update private.calendar_sync_jobs set lease_token=null,lease_until=null,next_attempt_at=now() where task_id=task_id_value;
    insert into private.calendar_sync_log(task_id,revision,outcome) values(task_id_value,revision_value,'stale');
    return false;
  end if;
  error_value:=case when error_code_value in ('CONFIG_INVALID','CONFIG_MISSING','GOOGLE_AUTH_FAILED',
    'GOOGLE_ACCESS_DENIED','GOOGLE_RATE_LIMIT','GOOGLE_UNAVAILABLE','GOOGLE_EVENT_GONE','TASK_INVALID','SYNC_UNAVAILABLE')
    then error_code_value when error_code_value is not null then 'SYNC_UNAVAILABLE' end;
  update public.work_tasks set
    calendar_sync_status=case when error_value is null then 'synced' else 'failed' end,
    calendar_sync_error=error_value,calendar_sync_attempts=job.attempts,
    calendar_event_id=case when error_value='GOOGLE_EVENT_GONE'
      then 'task'||replace(task_id_value::text,'-','')||'g'||to_hex(job.event_generation+1) else calendar_event_id end
    where id=task_id_value;
  update private.calendar_sync_jobs set lease_token=null,lease_until=null,
    next_attempt_at=now()+case when error_value is null then interval '15 minutes'
      else least(3600,60*power(2,least(job.attempts-1,6))) * interval '1 second' end,
    attempts=case when error_value is null then 0 else attempts end,
    event_generation=event_generation+case when error_value='GOOGLE_EVENT_GONE' then 1 else 0 end
    where task_id=task_id_value;
  insert into private.calendar_sync_log(task_id,revision,outcome,error_code)
    values(task_id_value,revision_value,case when error_value is null then 'synced' else 'failed' end,error_value);
  return true;
end;
$$;

create function public.work_task_list()
returns setof public.work_tasks language sql stable security invoker set search_path = '' as $$
  select * from public.work_tasks order by due_at,id;
$$;
-- Same visibility as work_tasks RLS: all and only active users. Definer
-- access is needed to count overdue private jobs, including periodic refreshes.
create function public.work_task_sync_warnings()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('failed_count',count(*) filter(where t.calendar_sync_status='failed'),
    'pending_count',count(*) filter(where t.calendar_sync_status='pending'),
    'overdue_sync_count',count(*) filter(where j.next_attempt_at<now()-interval '10 minutes'),
    'schedule_warning_count',count(*) filter(where t.schedule_warning is not null and t.status='pending'))
  from public.work_tasks t join private.calendar_sync_jobs j on j.task_id=t.id
  where t.managed_by_planning and private.current_user_is_active();
$$;

revoke all on function private.enqueue_calendar_task() from public,anon,authenticated;
revoke all on function private.queue_calendar_task() from public,anon,authenticated;
revoke all on function private.save_planned_task(text,uuid,boolean,boolean,timestamptz,timestamptz,uuid,jsonb,text,uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.project_ripening_tasks(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.project_shipping_task(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.ripening_plan_action(text,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function public.calendar_sync_claim(integer) from public,anon,authenticated;
revoke all on function public.calendar_sync_finish(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.calendar_sync_claim(integer),public.calendar_sync_finish(uuid,uuid,bigint,text) to service_role;
revoke all on function public.work_task_list(),public.work_task_sync_warnings() from public,anon;
grant execute on function public.work_task_list(),public.work_task_sync_warnings() to authenticated,service_role;

-- No HTTP call occurs until deployment supplies the worker URL and shared token
-- in Vault. The cron job only schedules delivery; transaction commits never
-- depend on Google or Edge Function availability.
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;
create function private.dispatch_calendar_sync()
returns void language plpgsql security definer set search_path = '' as $$
declare worker_url text; worker_token text;
begin
  select decrypted_secret into worker_url from vault.decrypted_secrets where name='calendar_sync_url';
  select decrypted_secret into worker_token from vault.decrypted_secrets where name='calendar_sync_token';
  if worker_url is null or worker_token is null then return; end if;
  if worker_url !~ '^https://' then raise exception 'calendar worker URL must use HTTPS'; end if;
  perform net.http_post(url:=worker_url,headers:=jsonb_build_object('Content-Type','application/json',
    'x-calendar-sync-token',worker_token),body:='{}'::jsonb,timeout_milliseconds:=90000);
end;
$$;
revoke all on function private.dispatch_calendar_sync() from public,anon,authenticated;
select cron.schedule('calendar-sync-dispatch','* * * * *','select private.dispatch_calendar_sync()');


-- Explicit administrator reconciliation also covers plans confirmed before
-- this migration. It does not fabricate a historical actor during deployment.
create function private.work_tasks_reconcile_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare source record; reason_value text; hours_value numeric; before_value jsonb; after_value jsonb; processed integer:=0;
begin
  if fn<>'work_tasks_reconcile' then raise exception 'unsupported task operation'; end if;
  perform private.customer_order_validate_keys(input_value,array['reason']);
  reason_value:=private.rpc_input_text(input_value,'reason',true);
  perform pg_advisory_xact_lock(53,0);
  select ethylene_processing_hours into hours_value from private.work_task_settings where singleton;
  for source in select o.* from public.orders o
    where o.status in ('confirmed','in_progress','partially_shipped')
      or exists(select 1 from public.work_tasks t where t.order_id=o.id and t.managed_by_planning)
    order by o.id for update
  loop
    perform private.project_shipping_task(source.id,actor,reason_value,correlation);
    processed:=processed+1;
  end loop;
  for source in select l.* from public.ripening_lots l
    where l.status in ('confirmed','in_progress')
      or exists(select 1 from public.work_tasks t where t.ripening_lot_id=l.id and t.managed_by_planning)
    order by l.id for update
  loop
    if source.master_snapshot->>'task_ethylene_processing_hours' is null then
      before_value:=to_jsonb(source);
      update public.ripening_lots set master_snapshot=master_snapshot||
        jsonb_build_object('task_ethylene_processing_hours',hours_value),version=version+1,updated_by=actor
        where id=source.id returning to_jsonb(ripening_lots) into after_value;
      insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
      values('ripening_lot',source.id,'update',before_value,after_value,reason_value,actor,correlation);
    end if;
    perform private.project_ripening_tasks(source.id,actor,reason_value,correlation);
    processed:=processed+1;
  end loop;
  return jsonb_build_object('processed_sources',processed);
end;
$$;
create or replace function private.work_tasks_reconcile_rpc(function_name_value text, req jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  raw_correlation text; correlation_value uuid; key_value uuid; input_value jsonb;
  actor_value uuid; hash_value text; outcome_value text; stored_value jsonb; envelope_value jsonb;
  code_value text; message_value text; details_value text; state_value text;
begin
  if req is null or jsonb_typeof(req)<>'object' then
    return private.rpc_error_envelope(null,'business','VALIDATION_FAILED',
      '要求の形式が正しくありません。',jsonb_build_object('field','req','reason','invalid_type'));
  end if;
  raw_correlation:=req->'meta'->>'correlation_id';
  correlation_value:=private.rpc_try_uuid_v4(raw_correlation);
  key_value:=private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key');
  input_value:=req->'input';
  if correlation_value is null then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'correlation_id が正しくありません。',jsonb_build_object('field','meta.correlation_id','reason','invalid_format'));
  end if;
  if key_value is null then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'idempotency_key が正しくありません。',jsonb_build_object('field','meta.idempotency_key','reason','invalid_format'));
  end if;
  if input_value is null or jsonb_typeof(input_value)<>'object' then
    return private.rpc_error_envelope(raw_correlation,'business','VALIDATION_FAILED',
      'input が正しくありません。',jsonb_build_object('field','input','reason','invalid_type'));
  end if;
  actor_value:=auth.uid();
  if actor_value is null then
    return private.rpc_error_envelope(raw_correlation,'auth','AUTH_REQUIRED','ログインが必要です。',null);
  end if;
  if not private.current_user_has_role('administrator') then
    return private.rpc_error_envelope(raw_correlation,'auth','AUTH_FORBIDDEN',
      'タスク再構成は管理者だけが行えます。',null);
  end if;
  hash_value:=encode(sha256(convert_to(function_name_value||':'||input_value::text,'utf8')),'hex');
  select claim_outcome,stored_response into outcome_value,stored_value
  from private.rpc_claim_idempotency(function_name_value,key_value,hash_value,actor_value);
  if outcome_value='replay' then
    return stored_value||jsonb_build_object('correlation_id',raw_correlation,'idempotent_replay',true);
  elsif outcome_value='reused' then
    return private.rpc_error_envelope(raw_correlation,'conflict','IDEMPOTENCY_KEY_REUSED',
      '同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。',null);
  end if;
  begin
    envelope_value:=private.rpc_success_envelope(raw_correlation,
      private.work_tasks_reconcile_action(function_name_value,input_value,actor_value,correlation_value));
  exception when sqlstate 'KW400' or sqlstate 'KW409' then
    get stacked diagnostics code_value=message_text,message_value=pg_exception_hint,
      details_value=pg_exception_detail,state_value=returned_sqlstate;
    envelope_value:=private.rpc_error_envelope(raw_correlation,
      case state_value when 'KW409' then 'conflict' else 'business' end,
      code_value,message_value,nullif(details_value,'')::jsonb);
  end;
  perform private.rpc_store_idempotency(key_value,envelope_value);
  return envelope_value;
end;
$$;

create function public.work_tasks_reconcile(req jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select private.rpc_log_response('work_tasks_reconcile',auth.uid(),
    private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
    private.work_tasks_reconcile_rpc('work_tasks_reconcile',req));
$$;
create function public.work_task_get(task_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select to_jsonb(t) from public.work_tasks t where id=task_id_value;
$$;
revoke all on function private.work_tasks_reconcile_action(text,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function private.work_tasks_reconcile_rpc(text,jsonb) from public,anon,authenticated;
revoke all on function public.work_tasks_reconcile(jsonb),public.work_task_get(uuid) from public,anon;
grant execute on function public.work_tasks_reconcile(jsonb),public.work_task_get(uuid) to authenticated,service_role;

commit;
