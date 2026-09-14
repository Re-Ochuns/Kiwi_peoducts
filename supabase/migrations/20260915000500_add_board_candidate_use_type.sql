begin;

create or replace function private.board_order_candidates(input_value jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ship_date date; ship_at timestamptz; variety uuid; grade uuid; weight numeric; result jsonb;
begin
  ship_date:=private.rpc_input_date(input_value,'scheduled_ship_date',true);
  variety:=private.rpc_input_uuid(input_value,'variety_id',true);
  grade:=private.rpc_input_uuid(input_value,'grade_id',true);
  weight:=private.rpc_input_weight(input_value,'ordered_weight_kg',true,false);
  ship_at:=(ship_date+time '09:00') at time zone 'Asia/Tokyo';
  if ship_at<=statement_timestamp() then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','出荷予定日は今後の日付を指定してください。');
  end if;
  if not exists(select 1 from public.varieties where id=variety and is_active)
    or not exists(select 1 from public.grades where id=grade and is_active) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','有効な品種・等級を指定してください。');
  end if;
  with cold as (
    select 'container'::text as kind,c.id,c.display_id,'sorted'::text as stage,
      c.current_weight_kg-c.reserved_weight_kg as available_weight_kg,
      ship_at-(r.ethylene_hours*interval '1 hour')-(r.rest_days*interval '24 hours') as planned_ethylene_at,
      ship_at as planned_completion_at,c.location_id,c.display_id as container_ids,
      md5(concat_ws('/',c.current_weight_kg,c.reserved_weight_kg,c.status,r.id,r.version)) as version, 'unassigned'::text as use_type
    from public.containers c
    join public.sorting_results s on s.id=c.sorting_result_id
    join public.receiving_lots receiving on receiving.id=s.receiving_lot_id
    join public.ripening_rules r on r.variety_id=c.variety_id
      and r.harvest_month=extract(month from receiving.received_on) and r.is_active
    where c.status='cold_storage' and not c.needs_review and c.variety_id=variety and c.grade_id=grade
      and c.current_weight_kg-c.reserved_weight_kg>=weight
      and ship_at-(r.ethylene_hours*interval '1 hour')-(r.rest_days*interval '24 hours')>=statement_timestamp()
  ), lots as (
    select l.*,
      case when l.status='confirmed' then
        (select coalesce(sum(reserved_weight_kg),0) from public.inventory_reservations
          where ripening_lot_id=l.id and status='active')
      else
        (select coalesce(sum(current_weight_kg),0) from public.containers
          where ripening_lot_id=l.id and status in ('ethylene_processing','resting','awaiting_ripeness_check','shippable'))
      end as physical,
      (select coalesce(sum(allocated_weight_kg),0) from public.ripening_allocations
        where ripening_lot_id=l.id and allocation_type='reserve') as reserve,
      (select coalesce(sum(greatest(0,a.allocated_weight_kg-private.shipped_weight(a.order_id,l.id))),0)
        from public.ripening_allocations a join public.orders o on o.id=a.order_id
        where a.ripening_lot_id=l.id and o.status not in ('cancelled','shipped')) as committed
    from public.ripening_lots l
    where l.variety_id=variety and l.grade_id=grade
      and l.status in ('confirmed','in_progress','completed') and not l.needs_review
      and l.calculated_rest_end_at<=ship_at
      and l.calculated_shippable_until is not null and l.calculated_best_before_at is not null
      and (l.status<>'confirmed' or not exists(
        select 1 from public.inventory_reservations r join public.containers c on c.id=r.container_id
        where r.ripening_lot_id=l.id and r.status='active'
          and (c.needs_review or c.status<>'cold_storage' or c.current_weight_kg<c.reserved_weight_kg)))
      and least(l.calculated_shippable_until,l.calculated_best_before_at)>ship_at
      and not exists(select 1 from public.containers c where c.ripening_lot_id=l.id
        and c.current_weight_kg>0 and (c.needs_review or c.status='expired'))
      and not exists(select 1 from public.containers c where c.ripening_lot_id=l.id and c.status='shippable'
        and (c.shippable_until is null or c.best_before_at is null
          or least(c.shippable_until,c.best_before_at)<=ship_at))
  ), ready as (
    select 'lot'::text as kind,l.id,l.display_id,
      case when l.status='confirmed' then 'sorted'
        when exists(select 1 from public.containers where ripening_lot_id=l.id and status='ethylene_processing') then 'ripening'
        when exists(select 1 from public.containers where ripening_lot_id=l.id and status in ('resting','awaiting_ripeness_check')) then 'resting'
        else 'shippable' end as stage,
      least(l.reserve,greatest(0,l.physical-l.committed)) as available_weight_kg,
      l.planned_ethylene_at,l.calculated_rest_end_at as planned_completion_at,
      l.storage_location_id as location_id,
      case when l.status='confirmed' then
        (select string_agg(c.display_id,'、' order by c.display_id) from public.inventory_reservations r
          join public.containers c on c.id=r.container_id where r.ripening_lot_id=l.id and r.status='active')
      else (select string_agg(display_id,'、' order by display_id) from public.containers
        where ripening_lot_id=l.id and current_weight_kg>0) end as container_ids,
      md5(concat_ws('/',l.version,l.physical,l.reserve,l.committed,l.calculated_rest_end_at,
        l.calculated_shippable_until,l.calculated_best_before_at)) as version, case when l.committed>0 then 'mixed' else 'reserve' end as use_type
    from lots l where least(l.reserve,greatest(0,l.physical-l.committed))>=weight
  ), candidates as (select * from cold union all select * from ready)
  select coalesce(jsonb_agg(to_jsonb(candidates) order by stage,display_id),'[]'::jsonb) into result from candidates;
  return result;
end;
$$;

commit;
