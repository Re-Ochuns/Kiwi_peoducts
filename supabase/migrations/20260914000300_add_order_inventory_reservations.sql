begin;

-- Existing rows remain legacy plan reservations; ownership is never inferred.
alter table public.orders add column inventory_first boolean not null default false;
alter table public.inventory_reservations add column owner_order_id uuid references public.orders(id);
alter table public.inventory_reservations alter column ripening_lot_id drop not null;
alter table public.inventory_reservations drop constraint inventory_reservations_ripening_lot_id_container_id_key;
alter table public.inventory_reservations add constraint reservation_has_owner check (ripening_lot_id is not null or owner_order_id is not null);
alter table public.inventory_reservations add constraint consumed_reservation_has_plan check (status <> 'consumed' or ripening_lot_id is not null);
create index inventory_reservations_order_idx on public.inventory_reservations(owner_order_id,status);
create or replace function private.apply_inventory_reservation_delta()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  lot_id uuid;
  container_id_value uuid;
  lot_row public.ripening_lots%rowtype;
  container_row public.containers%rowtype;
  reservation_delta numeric := 0;
  owner_row public.orders%rowtype;
begin
  lot_id := case when tg_op = 'DELETE' then old.ripening_lot_id else new.ripening_lot_id end;
  container_id_value := case when tg_op = 'DELETE' then old.container_id else new.container_id end;

  if tg_op = 'UPDATE' and row(new.owner_order_id, new.container_id)
    is distinct from row(old.owner_order_id, old.container_id) then
    raise exception 'inventory reservation cannot move' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.ripening_lot_id is distinct from old.ripening_lot_id then
    if old.status <> 'active' or new.status <> 'active' or new.owner_order_id is null
      or (new.ripening_lot_id is not null and old.ripening_lot_id is not null)
      or exists(select 1 from public.ripening_lots where id in (old.ripening_lot_id,new.ripening_lot_id) and status <> 'draft') then
      raise exception 'reservation transfer requires an owned active reservation and draft plan' using errcode='23514';
    end if;
  end if;
  if coalesce(new.owner_order_id,old.owner_order_id) is not null then
    select * into owner_row from public.orders where id=coalesce(new.owner_order_id,old.owner_order_id) for update;
    if tg_op <> 'DELETE' and new.status='active' and
      (owner_row.status not in ('draft','confirmed','in_progress','partially_shipped')) then
      raise exception 'inactive order cannot own an active reservation' using errcode='23514';
    end if;
  end if;
  select * into lot_row from public.ripening_lots where id = lot_id for update;
  select * into container_row from public.containers where id = container_id_value for update;

  if tg_op = 'INSERT' and lot_row.status <> 'draft' then
    raise exception 'reservation can only be added while lot is draft' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' and lot_row.status <> 'draft' then
    raise exception 'reservation can only be deleted while lot is draft' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if new.reserved_weight_kg is distinct from old.reserved_weight_kg
      and lot_row.status <> 'draft' then
      raise exception 'reservation weight can only be changed while lot is draft' using errcode = '23514';
    end if;
    if old.status = 'active' and new.status = 'released' and lot_row.status <> 'draft' then
      raise exception 'reservation can only be released while lot is draft' using errcode = '23514';
    end if;
    if old.status = 'active' and new.status = 'consumed' and lot_row.status not in ('confirmed', 'in_progress') then
      raise exception 'reservation can only be consumed after confirmation' using errcode = '23514';
    end if;
    if old.status <> new.status and not (old.status = 'active' and new.status in ('released', 'consumed')) then
      raise exception 'invalid reservation status transition' using errcode = '23514';
    end if;
    if old.status <> 'active' and new.reserved_weight_kg is distinct from old.reserved_weight_kg then
      raise exception 'finished reservation weight cannot be changed' using errcode = '23514';
    end if;
  end if;

  if tg_op <> 'DELETE' and new.status = 'active' then
    if container_row.status <> 'cold_storage' then
      raise exception 'only cold-storage inventory can be reserved' using errcode = '23514';
    end if;
    if new.owner_order_id is not null and row(container_row.variety_id,container_row.grade_id)
      is distinct from row(owner_row.variety_id,owner_row.grade_id) then
      raise exception 'container product does not match order' using errcode='23514';
    end if;
    if lot_id is not null and row(container_row.variety_id, container_row.grade_id)
      is distinct from row(lot_row.variety_id, lot_row.grade_id) then
      raise exception 'container product does not match ripening lot' using errcode = '23514';
    end if;
  end if;

  reservation_delta :=
    (case when tg_op <> 'DELETE' and new.status = 'active' then new.reserved_weight_kg else 0 end)
    - (case when tg_op <> 'INSERT' and old.status = 'active' then old.reserved_weight_kg else 0 end);

  update public.containers
  set reserved_weight_kg = reserved_weight_kg + reservation_delta
  where id = container_id_value
    and reserved_weight_kg + reservation_delta between 0 and current_weight_kg;

  if not found then
    raise exception 'reservation exceeds available container weight' using errcode = '23514';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;


-- Audit transfers as well as weight changes (including unplanned reservations).
create function private.audit_order_reservation() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if coalesce(new.owner_order_id,old.owner_order_id) is not null then
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
    values('inventory_reservation',coalesce(new.id,old.id),
      case tg_op when 'INSERT' then 'create' when 'DELETE' then 'delete' else 'update' end,
      case when tg_op<>'INSERT' then to_jsonb(old) end,
      case when tg_op='DELETE' then jsonb_build_object('id',old.id,'deleted',true) else to_jsonb(new) end,
      coalesce(nullif(current_setting('kiwi.reservation_reason',true),''),'受注予約調整'),
      coalesce(auth.uid(),new.updated_by,old.updated_by),
      nullif(current_setting('kiwi.reservation_correlation',true),'')::uuid);
  end if;
  return coalesce(new,old);
end; $$;
create trigger order_reservation_audit after insert or update or delete on public.inventory_reservations
for each row execute function private.audit_order_reservation();

create function private.set_order_reservations(order_value uuid, lines jsonb, actor uuid) returns void
language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; line jsonb; c public.containers%rowtype; requested numeric; planned numeric; total numeric:=0; seen uuid[]:=array[]::uuid[]; cid uuid;
begin
  select * into o from public.orders where id=order_value for update;
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) not between 1 and 100 then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','予約する在庫を1〜100件選択してください。');
  end if;
  -- Validate every row before releasing anything; locks are serialized with plan operations.
  for line in select value from jsonb_array_elements(lines) loop
    perform private.customer_order_validate_keys(line,array['container_id','reserved_weight_kg']);
    cid:=private.rpc_input_uuid(line,'container_id',true);
    requested:=private.rpc_input_weight(line,'reserved_weight_kg',true,false);
    if cid=any(seen) then perform private.rpc_fail('KW400','VALIDATION_FAILED','同じ在庫を重複指定できません。'); end if;
    seen:=array_append(seen,cid); total:=total+requested;
  end loop;
  if total<>o.ordered_weight_kg then perform private.rpc_fail('KW400','ORDER_RESERVATION_MISMATCH','注文量と在庫予約の合計を一致させてください。'); end if;
  if exists(select 1 from public.inventory_reservations where owner_order_id=o.id and status in ('active','consumed') and ripening_lot_id is not null and not(container_id=any(seen))) then
    perform private.rpc_fail('KW400','ORDER_RESERVATION_PLANNED','計画に引き継いだ在庫は先に追熟計画を見直してください。');
  end if;
  perform 1 from public.containers where id=any(seen) order by id for update;
  update public.inventory_reservations set status='released',released_at=now(),updated_by=actor
    where owner_order_id=o.id and ripening_lot_id is null and status='active';
  for line in select value from jsonb_array_elements(lines) loop
    cid:=(line->>'container_id')::uuid;
    requested:=(line->>'reserved_weight_kg')::numeric;
    select coalesce(sum(reserved_weight_kg),0) into planned from public.inventory_reservations
      where owner_order_id=o.id and container_id=cid and ripening_lot_id is not null and status in ('active','consumed');
    if planned>requested then perform private.rpc_fail('KW400','ORDER_RESERVATION_PLANNED','計画済みの予約量より少なくできません。先に追熟計画を見直してください。'); end if;
    requested:=requested-planned;
    select * into c from public.containers where id=cid;
    if not found or c.variety_id<>o.variety_id or c.grade_id<>o.grade_id or (requested>0 and (c.status<>'cold_storage' or c.current_weight_kg-c.reserved_weight_kg<requested)) then
      perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','選択した在庫の利用可能量が変わりました。在庫を再選択してください。');
    end if;
    if requested>0 then
      insert into public.inventory_reservations(owner_order_id,container_id,reserved_weight_kg,created_by,updated_by)
      values(o.id,cid,requested,actor,actor);
    end if;
  end loop;
end; $$;

alter function private.customer_order_action(text,jsonb,uuid,uuid) rename to customer_order_action_before_inventory_first;
create function private.customer_order_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; oid uuid; o public.orders%rowtype; plan public.ripening_lots%rowtype; allocation_row public.ripening_allocations%rowtype;
begin
  perform pg_advisory_xact_lock(53,0);
  perform set_config('kiwi.reservation_reason',coalesce(input_value->>'reason','受注・在庫予約を確定'),true);
  perform set_config('kiwi.reservation_correlation',correlation::text,true);
  if fn in ('order_register','order_update') then
    if fn='order_update' then
      oid:=private.rpc_input_uuid(input_value,'order_id',true);
      select * into o from public.orders where id=oid for update;
      if o.inventory_first and not(input_value ? 'reservations') then
        perform private.rpc_fail('KW400','ORDER_RESERVATION_REQUIRED','在庫選択に対応した画面を再読み込みしてください。');
      end if;
      if input_value ? 'reservations' and not o.inventory_first and o.allocated_weight_kg>0 then
        perform private.rpc_fail('KW400','ORDER_RESERVATION_PLANNED','既存受注の追熟計画を取り消してから在庫を選択してください。');
      end if;
    end if;
    result:=private.customer_order_action_before_inventory_first(fn,input_value-'reservations',actor,correlation);
    oid:=(result->>'id')::uuid;
    if fn='order_register' or input_value ? 'reservations' then
      update public.orders set inventory_first=true where id=oid;
    end if;
    if input_value ? 'reservations' then
      perform private.set_order_reservations(oid,input_value->'reservations',actor);
      result:=private.customer_order_action_before_inventory_first('order_confirm',jsonb_build_object(
        'order_id',oid,'expected_version',(result->>'version')::bigint,'reason','受注・在庫予約を確定'),actor,correlation);
    end if;
    return result;
  end if;
  if fn in ('order_confirm','order_cancel') then
    oid:=private.rpc_input_uuid(input_value,'order_id',true);
    select * into o from public.orders where id=oid for update;
    if fn='order_confirm' and o.inventory_first and
      (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations where owner_order_id=oid and status='active')<>o.ordered_weight_kg then
      perform private.rpc_fail('KW400','ORDER_RESERVATION_REQUIRED','受注を編集して在庫を選択し、受注・在庫予約を確定してください。');
    end if;
    if fn='order_cancel' and o.inventory_first then
      if o.version<>private.rpc_input_positive_int(input_value,'expected_version',true) or o.status not in ('draft','confirmed') then
        perform private.rpc_fail('KW409','CONFLICT_STALE','受注の状態が変わりました。再読み込みしてください。');
      end if;
      for plan in select l.* from public.ripening_lots l where l.id in
        (select ripening_lot_id from public.ripening_allocations where order_id=oid) order by l.id for update loop
        if plan.status not in ('draft','confirmed') then perform private.rpc_fail('KW409','CONFLICT_STALE','作業開始後の受注は取り消せません。'); end if;
        update public.ripening_lots set status='draft',needs_review=true,version=version+1,updated_by=actor where id=plan.id;
        for allocation_row in select * from public.ripening_allocations where order_id=oid and ripening_lot_id=plan.id loop
          insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
          values('ripening_allocation',allocation_row.id,'delete',to_jsonb(allocation_row),jsonb_build_object('id',allocation_row.id,'deleted',true),input_value->>'reason',actor,correlation);
        end loop;
        delete from public.ripening_allocations where order_id=oid and ripening_lot_id=plan.id;
        perform private.project_ripening_tasks(plan.id,actor,input_value->>'reason',correlation);
        insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
        select 'ripening_lot',id,'update',to_jsonb(plan),to_jsonb(l),input_value->>'reason',actor,correlation from public.ripening_lots l where id=plan.id;
      end loop;
      update public.inventory_reservations set status='released',released_at=now(),updated_by=actor where owner_order_id=oid and status='active';
    end if;
  end if;
  return private.customer_order_action_before_inventory_first(fn,input_value,actor,correlation);
end; $$;

-- Move only reservations owned by the allocated orders, within the requested source amounts.
create function private.transfer_order_reservations(lot_value uuid,data_value jsonb,actor uuid) returns void
language plpgsql security definer set search_path='' as $$
declare a jsonb; source_line jsonb; r public.inventory_reservations%rowtype; needed numeric; budget numeric; take_value numeric;
begin
  for a in select value from jsonb_array_elements(data_value->'allocations') order by value->>'order_id' loop
    if a->>'allocation_type'<>'order' or not exists(select 1 from public.orders where id=(a->>'order_id')::uuid and inventory_first) then continue; end if;
    needed:=(a->>'allocated_weight_kg')::numeric;
    for source_line in select value from jsonb_array_elements(data_value->'reservations') loop
      select (source_line->>'reserved_weight_kg')::numeric-coalesce(sum(reserved_weight_kg),0) into budget
        from public.inventory_reservations where ripening_lot_id=lot_value and container_id=(source_line->>'container_id')::uuid and status='active';
      for r in select * from public.inventory_reservations where owner_order_id=(a->>'order_id')::uuid
        and ripening_lot_id is null and status='active' and container_id=(source_line->>'container_id')::uuid order by id for update loop
        take_value:=least(needed,budget,r.reserved_weight_kg);
        if take_value<=0 then exit; end if;
        if take_value=r.reserved_weight_kg then
          update public.inventory_reservations set ripening_lot_id=lot_value,updated_by=actor where id=r.id;
        else
          update public.inventory_reservations set reserved_weight_kg=reserved_weight_kg-take_value,updated_by=actor where id=r.id;
          insert into public.inventory_reservations(owner_order_id,ripening_lot_id,container_id,reserved_weight_kg,created_by,updated_by)
          values(r.owner_order_id,lot_value,r.container_id,take_value,actor,actor);
        end if;
        needed:=needed-take_value; budget:=budget-take_value;
      end loop;
    end loop;
    if needed<>0 then perform private.rpc_fail('KW400','ORDER_RESERVATION_UNAVAILABLE','この受注の予約在庫と内訳量を確認してください。予約したコンテナから計画してください。'); end if;
  end loop;
end; $$;
create or replace function private.ripening_plan_action_without_tasks(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  lot_value uuid; lot_row public.ripening_lots%rowtype; data_value jsonb; line jsonb;
  before_value jsonb; after_value jsonb; entry record; old_row jsonb; new_row jsonb;
  orders_value uuid[]; containers_value uuid[]; reason_value text; expected bigint;
  source public.containers%rowtype; order_row public.orders%rowtype;
  requested numeric; operation_value text;
begin
  perform pg_advisory_xact_lock(53,0);
  perform set_config('kiwi.reservation_reason',coalesce(input_value->>'reason','追熟計画へ予約を引き継ぎ'),true);
  perform set_config('kiwi.reservation_correlation',correlation::text,true);
  if fn not in ('ripening_plan_register','ripening_plan_update','ripening_plan_confirm','ripening_plan_cancel') then
    raise exception 'unsupported ripening RPC';
  end if;
  if fn in ('ripening_plan_register','ripening_plan_update') then
    perform private.customer_order_validate_keys(input_value,
      case when fn='ripening_plan_register' then array[]::text[]
      else array['ripening_lot_id','expected_version'] end ||
      array['variety_id','grade_id','total_weight_kg','storage_location_id',
        'planned_ethylene_at','planned_completion_at','assigned_worker_id','notes',
        'allocations','reservations','reason']);
    data_value := private.ripening_plan_input(input_value);
  else
    perform private.customer_order_validate_keys(input_value,array['ripening_lot_id','expected_version','reason']);
  end if;
  reason_value := coalesce(private.rpc_input_text(input_value,'reason',fn<>'ripening_plan_register'),'追熟計画登録');
  if fn='ripening_plan_register' then
    lot_value := gen_random_uuid();
  else
    lot_value := private.rpc_input_uuid(input_value,'ripening_lot_id',true);
    expected := private.rpc_input_positive_int(input_value,'expected_version',true);
    select * into lot_row from public.ripening_lots where id=lot_value for update;
    if not found then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟計画が見つかりません。');
    end if;
    if lot_row.version<>expected or lot_row.status not in ('draft','confirmed')
      or (fn='ripening_plan_confirm' and lot_row.status<>'draft')
      or exists(select 1 from public.inventory_reservations where ripening_lot_id=lot_value and status='consumed') then
      perform private.rpc_fail('KW409','CONFLICT_STALE','計画が更新されたか作業が開始されています。',
        jsonb_build_object('current',to_jsonb(lot_row)));
    end if;
  end if;
  select coalesce(array_agg(distinct id),array[]::uuid[]) into orders_value from (
    select order_id id from public.ripening_allocations where ripening_lot_id=lot_value and order_id is not null
    union select (value->>'order_id')::uuid from jsonb_array_elements(data_value->'allocations')
      where value->>'order_id' is not null) ids;
  select coalesce(array_agg(distinct id),array[]::uuid[]) into containers_value from (
    select container_id id from public.inventory_reservations where ripening_lot_id=lot_value
    union select (value->>'container_id')::uuid from jsonb_array_elements(data_value->'reservations')) ids;
  perform 1 from public.orders where id=any(orders_value) order by id for update;
  perform 1 from public.containers where id=any(containers_value) order by id for update;
  before_value := private.ripening_audit_snapshot(lot_value,orders_value,containers_value);

  if fn='ripening_plan_register' then
    insert into public.ripening_lots(id,display_id,variety_id,grade_id,total_weight_kg,
      storage_location_id,planned_ethylene_at,planned_completion_at,assigned_worker_id,notes,created_by,updated_by)
    values(lot_value,private.next_display_id('追熟',extract(year from
      (data_value->>'planned_ethylene_at')::timestamptz at time zone 'Asia/Tokyo')::integer),
      (data_value->>'variety_id')::uuid,(data_value->>'grade_id')::uuid,
      (data_value->>'total_weight_kg')::numeric,(data_value->>'storage_location_id')::uuid,
      (data_value->>'planned_ethylene_at')::timestamptz,(data_value->>'planned_completion_at')::timestamptz,
      (data_value->>'assigned_worker_id')::uuid,data_value->>'notes',actor,actor);
  elsif fn in ('ripening_plan_update','ripening_plan_cancel') then
    update public.ripening_lots set status='draft',updated_by=actor where id=lot_value;
    update public.inventory_reservations set ripening_lot_id=null,updated_by=actor
      where ripening_lot_id=lot_value and owner_order_id is not null and status='active';
    delete from public.ripening_allocations where ripening_lot_id=lot_value;
    if fn='ripening_plan_cancel' then
      update public.inventory_reservations set status='released',released_at=now(),updated_by=actor
        where ripening_lot_id=lot_value and status='active';
      update public.ripening_lots set status='cancelled',needs_review=false,
        version=version+1,updated_by=actor where id=lot_value;
    else
      delete from public.inventory_reservations where ripening_lot_id=lot_value;
      update public.ripening_lots set
        variety_id=(data_value->>'variety_id')::uuid,grade_id=(data_value->>'grade_id')::uuid,
        total_weight_kg=(data_value->>'total_weight_kg')::numeric,
        storage_location_id=(data_value->>'storage_location_id')::uuid,
        assigned_worker_id=(data_value->>'assigned_worker_id')::uuid,
        planned_ethylene_at=(data_value->>'planned_ethylene_at')::timestamptz,
        planned_completion_at=(data_value->>'planned_completion_at')::timestamptz,
        notes=data_value->>'notes',needs_review=true,version=version+1,updated_by=actor where id=lot_value;
    end if;
  end if;

  if fn in ('ripening_plan_register','ripening_plan_update') then
    for line in select value from jsonb_array_elements(data_value->'allocations') loop
      requested := (line->>'allocated_weight_kg')::numeric;
      if line->>'allocation_type'='order' then
        select * into order_row from public.orders where id=(line->>'order_id')::uuid;
        if not found or order_row.status not in ('confirmed','in_progress','partially_shipped')
          or order_row.variety_id<>(data_value->>'variety_id')::uuid
          or order_row.grade_id<>(data_value->>'grade_id')::uuid
          or order_row.allocated_weight_kg+requested>order_row.ordered_weight_kg then
          perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','受注の状態・品種・等級・未割当量を確認してください。',
            jsonb_build_object('order_id',line->>'order_id'));
        end if;
      end if;
      insert into public.ripening_allocations(ripening_lot_id,allocation_type,order_id,
        allocated_weight_kg,notes,created_by,updated_by)
      values(lot_value,line->>'allocation_type',(line->>'order_id')::uuid,requested,line->>'notes',actor,actor);
    end loop;
    perform private.transfer_order_reservations(lot_value,data_value,actor);
    for line in select value from jsonb_array_elements(data_value->'reservations') loop
      select (line->>'reserved_weight_kg')::numeric-coalesce(sum(reserved_weight_kg),0) into requested
        from public.inventory_reservations where ripening_lot_id=lot_value and container_id=(line->>'container_id')::uuid and status='active';
      if requested=0 then continue; end if;
      select * into source from public.containers where id=(line->>'container_id')::uuid;
      if not found or source.status<>'cold_storage'
        or source.variety_id<>(data_value->>'variety_id')::uuid
        or source.grade_id<>(data_value->>'grade_id')::uuid
        or source.current_weight_kg-source.reserved_weight_kg<requested then
        perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','冷蔵在庫の状態・品種・等級・使用可能量を確認してください。',
          jsonb_build_object('container_id',line->>'container_id','requested_weight_kg',requested));
      end if;
      insert into public.inventory_reservations(ripening_lot_id,container_id,reserved_weight_kg,notes,created_by,updated_by)
      values(lot_value,source.id,requested,line->>'notes',actor,actor);
    end loop;
  elsif fn='ripening_plan_confirm' then
    -- Validate the persisted draft, including masters and orders changed since creation.
    perform private.ripening_plan_input(jsonb_build_object(
      'variety_id',lot_row.variety_id,'grade_id',lot_row.grade_id,'total_weight_kg',lot_row.total_weight_kg,
      'storage_location_id',lot_row.storage_location_id,'assigned_worker_id',lot_row.assigned_worker_id,
      'planned_ethylene_at',to_char(lot_row.planned_ethylene_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'planned_completion_at',to_char(lot_row.planned_completion_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'allocations','[]'::jsonb,'reservations','[]'::jsonb));
    if lot_row.allocated_weight_kg<>lot_row.total_weight_kg
      or (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
        where ripening_lot_id=lot_value and status='active')<>lot_row.total_weight_kg then
      perform private.rpc_fail('KW400','RIPENING_WEIGHT_MISMATCH','内訳・予約合計を追熟重量と一致させてください。');
    end if;
    if exists(select 1 from public.ripening_allocations a join public.orders o on o.id=a.order_id
      where a.ripening_lot_id=lot_value and (o.status not in ('confirmed','in_progress','partially_shipped')
        or o.variety_id<>lot_row.variety_id or o.grade_id<>lot_row.grade_id)) then
      perform private.rpc_fail('KW400','ORDER_UNAVAILABLE','受注を再確認してください。');
    end if;
    if exists(select 1 from public.inventory_reservations r join public.containers c on c.id=r.container_id
      where r.ripening_lot_id=lot_value and r.status='active' and
        (c.status<>'cold_storage' or c.variety_id<>lot_row.variety_id or c.grade_id<>lot_row.grade_id)) then
      perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','予約在庫を再確認してください。');
    end if;
    update public.ripening_lots set status='confirmed',needs_review=false,version=version+1,updated_by=actor
      where id=lot_value;
  end if;
  after_value := private.ripening_audit_snapshot(lot_value,orders_value,containers_value);
  for entry in select key from jsonb_object_keys(before_value||after_value) key loop
    old_row := before_value->entry.key; new_row := after_value->entry.key;
    if old_row is not distinct from new_row then continue; end if;
    operation_value := case when old_row is null then 'create' when new_row is null then 'delete'
      when old_row->'data'->>'status' is distinct from new_row->'data'->>'status' then 'transition' else 'update' end;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,reason,changed_by,correlation_id)
    values(coalesce(new_row,old_row)->>'entity',(coalesce(new_row,old_row)->>'id')::uuid,operation_value,
      old_row->'data',coalesce(new_row->'data',jsonb_build_object('id',old_row->>'id','deleted',true)),
      reason_value,actor,correlation);
  end loop;
  return public.ripening_plan_get(lot_value);
end;
$$;


alter function public.order_get(uuid) rename to order_get_before_inventory_first;
create function public.order_get(order_id_value uuid) returns jsonb language sql stable security invoker set search_path='' as $$
  select public.order_get_before_inventory_first(order_id_value)||jsonb_build_object('reservations',coalesce((
    select jsonb_agg(to_jsonb(r)||jsonb_build_object('display_id',c.display_id) order by c.display_id,r.id)
    from public.inventory_reservations r join public.containers c on c.id=r.container_id
    where r.owner_order_id=order_id_value and r.status in ('active','consumed')),'[]'::jsonb));
$$;
create function public.order_inventory_available(search_value text default '', variety_value uuid default null, grade_value uuid default null, offset_value integer default 0, order_value uuid default null)
returns setof jsonb language sql stable security invoker set search_path='' as $$
  select to_jsonb(c)||jsonb_build_object('available_weight_kg',c.current_weight_kg-c.reserved_weight_kg,
    'own_reserved_weight_kg',coalesce((select sum(r.reserved_weight_kg) from public.inventory_reservations r
      where r.owner_order_id=order_value and r.container_id=c.id and r.status='active'),0),
    'variety_label',v.code||' '||v.name,'grade_label',g.code,'location_label',l.name,
    'origin_label',rl.origin_name,'sorted_on',sl.sorted_on)
  from public.containers c join public.varieties v on v.id=c.variety_id join public.grades g on g.id=c.grade_id
  left join public.storage_locations l on l.id=c.location_id
  left join public.sorting_results sl on sl.id=c.sorting_result_id
  left join public.receiving_lots rl on rl.id=sl.receiving_lot_id
  where c.status='cold_storage' and (c.current_weight_kg>c.reserved_weight_kg or exists(select 1 from public.inventory_reservations r where r.owner_order_id=order_value and r.container_id=c.id and r.status='active'))
    and (variety_value is null or c.variety_id=variety_value) and (grade_value is null or c.grade_id=grade_value)
    and (coalesce(search_value,'')='' or c.display_id ilike '%'||search_value||'%')
  order by c.display_id,c.id limit 51 offset greatest(coalesce(offset_value,0),0);
$$;
create function public.ripening_order_inventory() returns setof jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('container_id',r.container_id,'order_id',r.owner_order_id,'weight_kg',sum(r.reserved_weight_kg))
 from public.inventory_reservations r join public.orders o on o.id=r.owner_order_id
 where r.ripening_lot_id is null and r.status='active' and o.status in ('confirmed','in_progress','partially_shipped')
 group by r.container_id,r.owner_order_id;
$$;
revoke all on function public.order_get(uuid),public.order_inventory_available(text,uuid,uuid,integer,uuid),public.ripening_order_inventory() from public,anon;
grant execute on function public.order_get(uuid),public.order_inventory_available(text,uuid,uuid,integer,uuid),public.ripening_order_inventory() to authenticated,service_role;
revoke all on function private.audit_order_reservation(),private.set_order_reservations(uuid,jsonb,uuid),private.customer_order_action(text,jsonb,uuid,uuid),private.transfer_order_reservations(uuid,jsonb,uuid) from public,anon,authenticated;
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
  reservation record;
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
    for reservation in select container_id,sum(reserved_weight_kg) reserved_weight_kg from public.inventory_reservations
      where ripening_lot_id=lot_id and status='active' group by container_id order by container_id
    loop
      select * into source from public.containers where id=reservation.container_id;
      if source.status<>'cold_storage' or source.variety_id<>lot.variety_id
        or source.grade_id<>lot.grade_id or source.current_weight_kg<source.reserved_weight_kg then
        perform private.rpc_fail('KW400','INVENTORY_UNAVAILABLE','予約元在庫を再確認してください。');
      end if;
      update public.inventory_reservations set status='consumed',consumed_at=actual_value,updated_by=actor
        where ripening_lot_id=lot_id and container_id=reservation.container_id and status='active';
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
create or replace function private.release_order_reservations(
  lot_id_value uuid, release_weight_value numeric, actor_id_value uuid,
  reason_value text, correlation_id_value uuid
)
returns void language plpgsql set search_path = '' as $$
declare
  remaining_value numeric := release_weight_value;
  reservation_row public.inventory_reservations%rowtype;
  reservation_after public.inventory_reservations%rowtype;
  container_before jsonb;
  container_after jsonb;
begin
  for reservation_row in
    select * from public.inventory_reservations r
    where r.ripening_lot_id = lot_id_value and r.status = 'active' and r.owner_order_id is null
    order by r.created_at desc, r.id desc for update
  loop
    exit when remaining_value <= 0;
    select to_jsonb(c) into container_before from public.containers c
    where c.id = reservation_row.container_id for update;
    if reservation_row.reserved_weight_kg <= remaining_value then
      update public.inventory_reservations
      set status = 'released', released_at = now(), updated_by = actor_id_value
      where id = reservation_row.id returning * into reservation_after;
      remaining_value := remaining_value - reservation_row.reserved_weight_kg;
    else
      update public.inventory_reservations
      set reserved_weight_kg = reserved_weight_kg - remaining_value, updated_by = actor_id_value
      where id = reservation_row.id returning * into reservation_after;
      remaining_value := 0;
    end if;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values('inventory_reservation',reservation_row.id,
      case when reservation_after.status <> reservation_row.status then 'transition' else 'update' end,
      to_jsonb(reservation_row),to_jsonb(reservation_after),reason_value,actor_id_value,correlation_id_value);
    select to_jsonb(c) into container_after from public.containers c where c.id=reservation_row.container_id;
    insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
      reason,changed_by,correlation_id)
    values('container',reservation_row.container_id,'update',container_before,container_after,
      reason_value,actor_id_value,correlation_id_value);
  end loop;
end;
$$;


create unique index inventory_reservations_legacy_source_key on public.inventory_reservations(ripening_lot_id,container_id) where owner_order_id is null;
commit;
