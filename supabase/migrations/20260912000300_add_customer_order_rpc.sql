begin;

-- Deletions retain a non-null tombstone in after_data for existing consumers.
alter table public.change_history drop constraint change_history_operation_check;
alter table public.change_history add constraint change_history_operation_check
  check (operation in ('create', 'update', 'transition', 'correct', 'delete'));

alter table public.customers
  add column version bigint not null default 1 check (version > 0);
alter table public.shipping_destinations
  add column version bigint not null default 1 check (version > 0);

create or replace function private.customer_order_validate_keys(input_value jsonb, allowed_keys text[])
returns void language plpgsql set search_path = '' as $$
declare key_value text;
begin
  for key_value in select jsonb_object_keys(input_value) loop
    if not (key_value = any(allowed_keys)) then
      perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '未対応の入力項目が指定されています。',
        jsonb_build_object('field', key_value, 'reason', 'unknown_field'));
    end if;
  end loop;
end;
$$;

create or replace function private.customer_input(input_value jsonb)
returns jsonb language sql set search_path = '' as $$
  select jsonb_build_object(
    'customer_code', private.rpc_input_text(input_value, 'customer_code', true),
    'name', private.rpc_input_text(input_value, 'name', true),
    'nickname', private.rpc_input_text(input_value, 'nickname', false),
    'postal_code', private.rpc_input_text(input_value, 'postal_code', true),
    'address', private.rpc_input_text(input_value, 'address', true));
$$;

create or replace function private.destination_input(input_value jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare customer_id_value uuid;
begin
  customer_id_value := private.rpc_input_uuid(input_value, 'customer_id', true);
  if not exists (
    select 1 from public.customers c
    where c.id = customer_id_value and c.is_active for share
  ) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '顧客が見つからないか無効です。',
      jsonb_build_object('field', 'customer_id', 'reason', 'not_found'));
  end if;
  return jsonb_build_object(
    'customer_id', customer_id_value,
    'destination_name', private.rpc_input_text(input_value, 'destination_name', true),
    'recipient_name', private.rpc_input_text(input_value, 'recipient_name', true),
    'postal_code', private.rpc_input_text(input_value, 'postal_code', true),
    'address', private.rpc_input_text(input_value, 'address', true));
end;
$$;

create or replace function private.order_input(input_value jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  customer_id_value uuid;
  destination_id_value uuid;
  variety_id_value uuid;
  grade_id_value uuid;
  ordered_on_value date;
  scheduled_ship_on_value date;
  weight_value numeric;
  destination_row public.shipping_destinations%rowtype;
begin
  customer_id_value := private.rpc_input_uuid(input_value, 'customer_id', true);
  destination_id_value := private.rpc_input_uuid(input_value, 'shipping_destination_id', true);
  variety_id_value := private.rpc_input_uuid(input_value, 'variety_id', true);
  grade_id_value := private.rpc_input_uuid(input_value, 'grade_id', true);
  ordered_on_value := private.rpc_input_date(input_value, 'ordered_date', true);
  scheduled_ship_on_value := private.rpc_input_date(input_value, 'scheduled_ship_date', true);
  weight_value := private.rpc_input_weight(input_value, 'ordered_weight_kg', true, false);
  if scheduled_ship_on_value < ordered_on_value then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '出荷予定日は注文日以降を指定してください。',
      jsonb_build_object('field', 'scheduled_ship_date', 'reason', 'out_of_range'));
  end if;
  if not exists (
    select 1 from public.customers c where c.id = customer_id_value and c.is_active for share
  ) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '顧客が見つからないか無効です。',
      jsonb_build_object('field', 'customer_id', 'reason', 'not_found'));
  end if;
  select * into destination_row from public.shipping_destinations d
  where d.id = destination_id_value and d.customer_id = customer_id_value and d.is_active
  for share;
  if not found then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '配送先が顧客に属していないか無効です。',
      jsonb_build_object('field', 'shipping_destination_id', 'reason', 'not_found'));
  end if;
  if not exists (
    select 1 from public.varieties v where v.id = variety_id_value and v.is_active for share
  ) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '品種が見つからないか無効です。',
      jsonb_build_object('field', 'variety_id', 'reason', 'not_found'));
  end if;
  if not exists (
    select 1 from public.grades g where g.id = grade_id_value and g.is_active for share
  ) then
    perform private.rpc_fail('KW400', 'VALIDATION_FAILED', '等級が見つからないか無効です。',
      jsonb_build_object('field', 'grade_id', 'reason', 'not_found'));
  end if;
  return jsonb_build_object(
    'customer_id', customer_id_value,
    'shipping_destination_id', destination_id_value,
    'ordered_on', to_char(ordered_on_value, 'YYYY-MM-DD'),
    'scheduled_ship_on', to_char(scheduled_ship_on_value, 'YYYY-MM-DD'),
    'variety_id', variety_id_value, 'grade_id', grade_id_value,
    'ordered_weight_kg', weight_value,
    'notes', private.rpc_input_text(input_value, 'notes', false),
    'shipping_destination_snapshot', jsonb_build_object(
      'destination_name', destination_row.destination_name,
      'recipient_name', destination_row.recipient_name,
      'postal_code', destination_row.postal_code,
      'address', destination_row.address));
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
    where r.ripening_lot_id = lot_id_value and r.status = 'active'
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

create or replace function private.customer_order_action(
  function_name_value text, input_value jsonb, actor_id_value uuid, correlation_id_value uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  data_value jsonb;
  before_value jsonb;
  customer_row public.customers%rowtype;
  destination_row public.shipping_destinations%rowtype;
  order_row public.orders%rowtype;
  entity_type_value text;
  entity_id_value uuid;
  operation_value text;
  reason_value text;
  expected_version_value bigint;
  affected_plans_value integer := 0;
  allocation_row public.ripening_allocations%rowtype;
  plan_row public.ripening_lots%rowtype;
  plan_after jsonb;
begin
  if function_name_value = 'customer_register' then
    perform private.customer_order_validate_keys(input_value,
      array['customer_code','name','nickname','postal_code','address','reason']);
    data_value := private.customer_input(input_value);
    if exists (select 1 from public.customers c
      where c.customer_code = data_value ->> 'customer_code') then
      perform private.rpc_fail('KW400', 'CUSTOMER_DUPLICATE', '同じ顧客コードが登録されています。',
        jsonb_build_object('field', 'customer_code', 'reason', 'duplicate'));
    end if;
    insert into public.customers
      (customer_code,name,nickname,postal_code,address,created_by,updated_by)
    values (data_value->>'customer_code',data_value->>'name',data_value->>'nickname',
      data_value->>'postal_code',data_value->>'address',actor_id_value,actor_id_value)
    returning * into customer_row;
    entity_type_value := 'customer'; entity_id_value := customer_row.id;
    operation_value := 'create';
    reason_value := coalesce(private.rpc_input_text(input_value,'reason',false),'顧客登録');
    data_value := to_jsonb(customer_row);

  elsif function_name_value = 'customer_update' then
    perform private.customer_order_validate_keys(input_value,
      array['customer_id','expected_version','customer_code','name','nickname','postal_code','address','reason']);
    entity_id_value := private.rpc_input_uuid(input_value,'customer_id',true);
    expected_version_value := private.rpc_input_positive_int(input_value,'expected_version',true);
    reason_value := private.rpc_input_text(input_value,'reason',true);
    data_value := private.customer_input(input_value);
    select * into customer_row from public.customers where id = entity_id_value for update;
    if not found then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','顧客が見つかりません。',
        jsonb_build_object('field','customer_id','reason','not_found'));
    end if;
    if customer_row.version <> expected_version_value then
      perform private.rpc_fail('KW409','CONFLICT_STALE','顧客は他の操作で更新されています。',
        jsonb_build_object('current',jsonb_build_object('customer_id',customer_row.id,'version',customer_row.version)));
    end if;
    if exists (select 1 from public.customers c
      where c.customer_code = data_value->>'customer_code' and c.id <> entity_id_value) then
      perform private.rpc_fail('KW400','CUSTOMER_DUPLICATE','同じ顧客コードが登録されています。',
        jsonb_build_object('field','customer_code','reason','duplicate'));
    end if;
    before_value := to_jsonb(customer_row);
    update public.customers set customer_code=data_value->>'customer_code',
      name=data_value->>'name',nickname=data_value->>'nickname',
      postal_code=data_value->>'postal_code',address=data_value->>'address',
      version=version+1,updated_by=actor_id_value
    where id=entity_id_value returning * into customer_row;
    entity_type_value := 'customer'; operation_value := 'update'; data_value := to_jsonb(customer_row);

  elsif function_name_value = 'shipping_destination_register' then
    perform private.customer_order_validate_keys(input_value,
      array['customer_id','destination_name','recipient_name','postal_code','address','reason']);
    data_value := private.destination_input(input_value);
    if exists (select 1 from public.shipping_destinations d
      where d.customer_id=(data_value->>'customer_id')::uuid
        and d.destination_name=data_value->>'destination_name') then
      perform private.rpc_fail('KW400','SHIPPING_DESTINATION_DUPLICATE','同じ名称の配送先が登録されています。',
        jsonb_build_object('field','destination_name','reason','duplicate'));
    end if;
    insert into public.shipping_destinations
      (customer_id,destination_name,recipient_name,postal_code,address,created_by,updated_by)
    values ((data_value->>'customer_id')::uuid,data_value->>'destination_name',
      data_value->>'recipient_name',data_value->>'postal_code',data_value->>'address',
      actor_id_value,actor_id_value) returning * into destination_row;
    entity_type_value := 'shipping_destination'; entity_id_value := destination_row.id;
    operation_value := 'create';
    reason_value := coalesce(private.rpc_input_text(input_value,'reason',false),'配送先登録');
    data_value := to_jsonb(destination_row);

  elsif function_name_value = 'shipping_destination_update' then
    perform private.customer_order_validate_keys(input_value,
      array['shipping_destination_id','expected_version','customer_id','destination_name',
        'recipient_name','postal_code','address','reason']);
    entity_id_value := private.rpc_input_uuid(input_value,'shipping_destination_id',true);
    expected_version_value := private.rpc_input_positive_int(input_value,'expected_version',true);
    reason_value := private.rpc_input_text(input_value,'reason',true);
    data_value := private.destination_input(input_value);
    select * into destination_row from public.shipping_destinations where id=entity_id_value for update;
    if not found then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','配送先が見つかりません。',
        jsonb_build_object('field','shipping_destination_id','reason','not_found'));
    end if;
    if destination_row.customer_id <> (data_value->>'customer_id')::uuid then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','配送先の顧客は変更できません。',
        jsonb_build_object('field','customer_id','reason','immutable'));
    end if;
    if destination_row.version <> expected_version_value then
      perform private.rpc_fail('KW409','CONFLICT_STALE','配送先は他の操作で更新されています。',
        jsonb_build_object('current',jsonb_build_object(
          'shipping_destination_id',destination_row.id,'version',destination_row.version)));
    end if;
    if exists (select 1 from public.shipping_destinations d
      where d.customer_id=destination_row.customer_id
        and d.destination_name=data_value->>'destination_name' and d.id<>entity_id_value) then
      perform private.rpc_fail('KW400','SHIPPING_DESTINATION_DUPLICATE','同じ名称の配送先が登録されています。',
        jsonb_build_object('field','destination_name','reason','duplicate'));
    end if;
    before_value := to_jsonb(destination_row);
    update public.shipping_destinations set destination_name=data_value->>'destination_name',
      recipient_name=data_value->>'recipient_name',postal_code=data_value->>'postal_code',
      address=data_value->>'address',version=version+1,updated_by=actor_id_value
    where id=entity_id_value returning * into destination_row;
    entity_type_value := 'shipping_destination'; operation_value := 'update';
    data_value := to_jsonb(destination_row);

  elsif function_name_value = 'order_register' then
    perform private.customer_order_validate_keys(input_value,
      array['customer_id','shipping_destination_id','ordered_date','scheduled_ship_date',
        'variety_id','grade_id','ordered_weight_kg','notes','reason']);
    data_value := private.order_input(input_value);
    insert into public.orders (order_number,customer_id,shipping_destination_id,ordered_on,
      scheduled_ship_on,variety_id,grade_id,ordered_weight_kg,
      shipping_destination_snapshot,notes,created_by,updated_by)
    values (private.next_display_id('受注',extract(year from (data_value->>'ordered_on')::date)::integer),
      (data_value->>'customer_id')::uuid,(data_value->>'shipping_destination_id')::uuid,
      (data_value->>'ordered_on')::date,(data_value->>'scheduled_ship_on')::date,
      (data_value->>'variety_id')::uuid,(data_value->>'grade_id')::uuid,
      (data_value->>'ordered_weight_kg')::public.weight_kg,
      data_value->'shipping_destination_snapshot',data_value->>'notes',actor_id_value,actor_id_value)
    returning * into order_row;
    entity_type_value := 'order'; entity_id_value := order_row.id; operation_value := 'create';
    reason_value := coalesce(private.rpc_input_text(input_value,'reason',false),'受注下書き登録');
    data_value := to_jsonb(order_row);

  else
    entity_id_value := private.rpc_input_uuid(input_value,'order_id',true);
    expected_version_value := private.rpc_input_positive_int(input_value,'expected_version',true);
    reason_value := private.rpc_input_text(input_value,'reason',true);
    select * into order_row from public.orders where id=entity_id_value for update;
    if not found then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','受注が見つかりません。',
        jsonb_build_object('field','order_id','reason','not_found'));
    end if;
    if order_row.version <> expected_version_value then
      perform private.rpc_fail('KW409','CONFLICT_STALE','受注は他の操作で更新されています。',
        jsonb_build_object('current',jsonb_build_object(
          'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
    end if;
    before_value := to_jsonb(order_row);

    if function_name_value = 'order_update' then
      perform private.customer_order_validate_keys(input_value,
        array['order_id','expected_version','customer_id','shipping_destination_id',
          'ordered_date','scheduled_ship_date','variety_id','grade_id',
          'ordered_weight_kg','notes','reason']);
      if order_row.status not in ('draft','confirmed') then
        perform private.rpc_fail('KW409','CONFLICT_STALE','この状態の受注は変更できません。',
          jsonb_build_object('current',jsonb_build_object(
            'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
      end if;
      data_value := private.order_input(input_value);
      if (data_value->>'ordered_weight_kg')::numeric < order_row.allocated_weight_kg then
        perform private.rpc_fail('KW400','ORDER_WEIGHT_BELOW_ALLOCATED',
          '注文量を割当済み量より少なくできません。先に追熟計画を見直してください。',
          jsonb_build_object('ordered_weight_kg',(data_value->>'ordered_weight_kg')::numeric,
            'allocated_weight_kg',order_row.allocated_weight_kg));
      end if;
      if order_row.status='confirmed' then
        for plan_row in
          select l.* from public.ripening_lots l
          where l.id in (select a.ripening_lot_id from public.ripening_allocations a
            where a.order_id=order_row.id) and l.status in ('draft','confirmed')
          order by l.id for update
        loop
          update public.ripening_lots l set status='draft',
            needs_review=true,version=l.version+1,updated_by=actor_id_value
          where l.id=plan_row.id returning to_jsonb(l) into plan_after;
          insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
            reason,changed_by,correlation_id)
          values('ripening_lot',plan_row.id,
            case when plan_row.status='confirmed' then 'transition' else 'update' end,
            to_jsonb(plan_row),plan_after,reason_value,actor_id_value,correlation_id_value);
          affected_plans_value := affected_plans_value + 1;
        end loop;
      end if;
      update public.orders set customer_id=(data_value->>'customer_id')::uuid,
        shipping_destination_id=(data_value->>'shipping_destination_id')::uuid,
        ordered_on=(data_value->>'ordered_on')::date,
        scheduled_ship_on=(data_value->>'scheduled_ship_on')::date,
        variety_id=(data_value->>'variety_id')::uuid,grade_id=(data_value->>'grade_id')::uuid,
        ordered_weight_kg=(data_value->>'ordered_weight_kg')::public.weight_kg,
        shipping_destination_snapshot=case
          when order_row.shipping_destination_id=(data_value->>'shipping_destination_id')::uuid
            then order_row.shipping_destination_snapshot
          else data_value->'shipping_destination_snapshot' end,
        notes=data_value->>'notes',status=case when status='confirmed' then 'draft' else status end,
        version=version+1,updated_by=actor_id_value
      where id=order_row.id returning * into order_row;
      operation_value := 'update';

    elsif function_name_value = 'order_confirm' then
      perform private.customer_order_validate_keys(input_value,array['order_id','expected_version','reason']);
      if order_row.status<>'draft' then
        perform private.rpc_fail('KW409','CONFLICT_STALE','下書きの受注だけ確定できます。',
          jsonb_build_object('current',jsonb_build_object(
            'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
      end if;
      if not exists(select 1 from public.customers c where c.id=order_row.customer_id and c.is_active)
        or not exists(select 1 from public.shipping_destinations d
          where d.id=order_row.shipping_destination_id and d.customer_id=order_row.customer_id and d.is_active)
        or not exists(select 1 from public.varieties v where v.id=order_row.variety_id and v.is_active)
        or not exists(select 1 from public.grades g where g.id=order_row.grade_id and g.is_active) then
        perform private.rpc_fail('KW400','ORDER_REFERENCE_INACTIVE',
          '顧客、配送先、品種、等級のいずれかが無効です。',
          jsonb_build_object('reason','inactive_reference'));
      end if;
      update public.orders set status='confirmed',version=version+1,updated_by=actor_id_value
      where id=order_row.id returning * into order_row;
      operation_value := 'transition';

    elsif function_name_value = 'order_cancel' then
      perform private.customer_order_validate_keys(input_value,array['order_id','expected_version','reason']);
      if order_row.status not in ('draft','confirmed') then
        perform private.rpc_fail('KW409','CONFLICT_STALE','下書きまたは確定済みの受注だけキャンセルできます。',
          jsonb_build_object('current',jsonb_build_object(
            'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
      end if;
      if exists(select 1 from public.ripening_allocations a
        join public.ripening_lots l on l.id=a.ripening_lot_id
        where a.order_id=order_row.id and l.status not in ('draft','confirmed')) then
        perform private.rpc_fail('KW409','CONFLICT_STALE','作業開始後の受注はこの操作ではキャンセルできません。',
          jsonb_build_object('current',jsonb_build_object(
            'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
      end if;
      for plan_row in
        select l.* from public.ripening_lots l
        where l.id in (select a.ripening_lot_id from public.ripening_allocations a
          where a.order_id=order_row.id)
        order by l.id for update
      loop
        -- Recheck after locking, including a concurrent start of the plan.
        if plan_row.status not in ('draft','confirmed') then
          perform private.rpc_fail('KW409','CONFLICT_STALE',
            '作業開始後の受注はこの操作ではキャンセルできません。',
            jsonb_build_object('current',jsonb_build_object(
              'order_id',order_row.id,'status',order_row.status,'version',order_row.version)));
        end if;
        update public.ripening_lots l set status='draft',needs_review=true,
          version=l.version+1,updated_by=actor_id_value where l.id=plan_row.id;
        for allocation_row in select a.* from public.ripening_allocations a
          where a.order_id=order_row.id and a.ripening_lot_id=plan_row.id
          order by a.id for update
        loop
          delete from public.ripening_allocations where id=allocation_row.id;
          insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
            reason,changed_by,correlation_id)
          values('ripening_allocation',allocation_row.id,'delete',to_jsonb(allocation_row),
            jsonb_build_object('id',allocation_row.id,'deleted',true),
            reason_value,actor_id_value,correlation_id_value);
          perform private.release_order_reservations(plan_row.id,
            allocation_row.allocated_weight_kg,actor_id_value,reason_value,correlation_id_value);
        end loop;
        -- Include trigger-maintained allocation totals/use_type in the final snapshot.
        select to_jsonb(l) into plan_after from public.ripening_lots l where l.id=plan_row.id;
        insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
          reason,changed_by,correlation_id)
        values('ripening_lot',plan_row.id,
          case when plan_row.status='confirmed' then 'transition' else 'update' end,
          to_jsonb(plan_row),plan_after,reason_value,actor_id_value,correlation_id_value);
        affected_plans_value := affected_plans_value + 1;
      end loop;
      update public.orders set status='cancelled',version=version+1,updated_by=actor_id_value
      where id=order_row.id returning * into order_row;
      operation_value := 'transition';
    else
      raise exception 'unsupported customer/order RPC: %',function_name_value;
    end if;
    entity_type_value := 'order';
    data_value := to_jsonb(order_row)||jsonb_build_object('affected_plan_count',affected_plans_value);
  end if;

  insert into public.change_history(entity_type,entity_id,operation,before_data,after_data,
    reason,changed_by,correlation_id)
  values(entity_type_value,entity_id_value,operation_value,before_value,data_value,
    reason_value,actor_id_value,correlation_id_value);
  return data_value;
end;
$$;

create or replace function private.customer_order_rpc(function_name_value text, req jsonb)
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
      '顧客・受注の変更は管理者だけが行えます。',null);
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
      private.customer_order_action(function_name_value,input_value,actor_value,correlation_value));
  exception when sqlstate 'KW400' or sqlstate 'KW409' then
    get stacked diagnostics code_value=message_text,message_value=pg_exception_hint,
      details_value=pg_exception_detail,state_value=returned_sqlstate;
    envelope_value:=private.rpc_error_envelope(raw_correlation,
      case state_value when 'KW409' then 'conflict' else 'business' end,
      code_value,message_value,nullif(details_value,'')::jsonb);
    when unique_violation then
    envelope_value:=private.rpc_error_envelope(raw_correlation,'business',
      case
        when function_name_value like 'customer_%' then 'CUSTOMER_DUPLICATE'
        when function_name_value like 'shipping_destination_%' then 'SHIPPING_DESTINATION_DUPLICATE'
        else 'ORDER_DUPLICATE'
      end,
      '同じ値のデータがすでに登録されています。',
      jsonb_build_object('reason','duplicate'));
  end;
  perform private.rpc_store_idempotency(key_value,envelope_value);
  return envelope_value;
end;
$$;

do $$
declare function_name text;
begin
  foreach function_name in array array['customer_register','customer_update',
    'shipping_destination_register','shipping_destination_update',
    'order_register','order_update','order_confirm','order_cancel']
  loop
    execute format($fn$
      create or replace function public.%1$I(req jsonb) returns jsonb
      language sql security definer set search_path = '' as $body$
        select private.rpc_log_response(%2$L,auth.uid(),
          private.rpc_try_uuid_v4(req->'meta'->>'correlation_id'),
          private.rpc_try_uuid_v4(req->'meta'->>'idempotency_key'),
          private.customer_order_rpc(%2$L,req))
      $body$;
    $fn$,function_name,function_name);
    execute format('revoke all on function public.%I(jsonb) from public,anon',function_name);
    execute format('grant execute on function public.%I(jsonb) to authenticated,service_role',function_name);
  end loop;
end;
$$;

create or replace function public.customer_list(search_value text default null,include_inactive boolean default false)
returns table(customer_id uuid,customer_code text,name text,nickname text,postal_code text,
  address text,is_active boolean,version bigint,destination_count bigint,updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select c.id,c.customer_code,c.name,c.nickname,c.postal_code,c.address,c.is_active,c.version,
    count(d.id),c.updated_at from public.customers c
  left join public.shipping_destinations d on d.customer_id=c.id and d.is_active
  where (include_inactive or c.is_active) and
    (coalesce(btrim(search_value),'')='' or concat_ws(' ',c.customer_code,c.name,c.nickname,c.postal_code,c.address)
      ilike '%'||replace(replace(replace(btrim(search_value),chr(92),chr(92)||chr(92)),'%','\%'),'_','\_')||'%' escape '\')
  group by c.id order by c.customer_code,c.id;
$$;

create or replace function public.shipping_destination_list(customer_id_value uuid,include_inactive boolean default false)
returns table(shipping_destination_id uuid,customer_id uuid,destination_name text,recipient_name text,
  postal_code text,address text,is_active boolean,version bigint,updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select d.id,d.customer_id,d.destination_name,d.recipient_name,d.postal_code,d.address,
    d.is_active,d.version,d.updated_at from public.shipping_destinations d
  where d.customer_id=customer_id_value and (include_inactive or d.is_active)
  order by d.destination_name,d.id;
$$;

create or replace function public.customer_get(customer_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select to_jsonb(c)||jsonb_build_object('destinations',coalesce((
    select jsonb_agg(to_jsonb(d) order by d.destination_name,d.id)
    from public.shipping_destinations d where d.customer_id=c.id),'[]'::jsonb))
  from public.customers c where c.id=customer_id_value;
$$;

create or replace function public.order_list(status_value text default null,search_value text default null)
returns table(order_id uuid,order_number text,customer_id uuid,customer_name text,customer_nickname text,
  ordered_on date,scheduled_ship_on date,variety_id uuid,grade_id uuid,
  ordered_weight_kg public.weight_kg,allocated_weight_kg public.weight_kg,
  shortage_weight_kg numeric,status text,version bigint,updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select o.id,o.order_number,o.customer_id,c.name,c.nickname,o.ordered_on,o.scheduled_ship_on,
    o.variety_id,o.grade_id,o.ordered_weight_kg,o.allocated_weight_kg,
    (o.ordered_weight_kg-o.allocated_weight_kg)::numeric,o.status,o.version,o.updated_at
  from public.orders o join public.customers c on c.id=o.customer_id
  where (status_value is null or o.status=status_value)
    and (coalesce(btrim(search_value),'')='' or concat_ws(' ',o.order_number,c.name,c.nickname)
      ilike '%'||replace(replace(replace(btrim(search_value),chr(92),chr(92)||chr(92)),'%','\%'),'_','\_')||'%' escape '\')
  order by o.scheduled_ship_on,o.order_number,o.id;
$$;

create or replace function public.order_get(order_id_value uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select to_jsonb(o)||jsonb_build_object(
    'customer',jsonb_build_object('customer_code',c.customer_code,'name',c.name,'nickname',c.nickname),
    'shortage_weight_kg',o.ordered_weight_kg-o.allocated_weight_kg,
    'ripening_allocations',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id)
      from public.ripening_allocations a where a.order_id=o.id),'[]'::jsonb))
  from public.orders o join public.customers c on c.id=o.customer_id where o.id=order_id_value;
$$;

revoke all on function private.customer_order_validate_keys(jsonb,text[]) from public,anon,authenticated;
revoke all on function private.customer_input(jsonb) from public,anon,authenticated;
revoke all on function private.destination_input(jsonb) from public,anon,authenticated;
revoke all on function private.order_input(jsonb) from public,anon,authenticated;
revoke all on function private.release_order_reservations(uuid,numeric,uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.customer_order_action(text,jsonb,uuid,uuid) from public,anon,authenticated;
revoke all on function private.customer_order_rpc(text,jsonb) from public,anon,authenticated;
revoke all on function public.customer_list(text,boolean) from public,anon;
revoke all on function public.shipping_destination_list(uuid,boolean) from public,anon;
revoke all on function public.customer_get(uuid) from public,anon;
revoke all on function public.order_list(text,text) from public,anon;
revoke all on function public.order_get(uuid) from public,anon;
grant execute on function public.customer_list(text,boolean) to authenticated,service_role;
grant execute on function public.shipping_destination_list(uuid,boolean) to authenticated,service_role;
grant execute on function public.customer_get(uuid) to authenticated,service_role;
grant execute on function public.order_list(text,text) to authenticated,service_role;
grant execute on function public.order_get(uuid) to authenticated,service_role;

comment on function public.order_register(jsonb) is
  'Registers an idempotent draft order with an immutable shipping destination snapshot.';
comment on function public.order_update(jsonb) is
  'Updates a draft or confirmed order and marks related ripening plans for review.';
comment on function public.order_cancel(jsonb) is
  'Cancels a pre-work order, removes its allocations, and releases corresponding reservations.';

commit;
