begin;

-- 追熟条件は年度をまたいで再利用し、品種と受入月だけで一意にする。
-- harvest_year は既存RPCとの互換性のため内部値を残すが、利用者入力には使用しない。
with ranked as (
  select id,row_number() over (
    partition by harvest_month,variety_id
    order by harvest_year desc,updated_at desc,id
  ) as position
  from public.ripening_rules where is_active
)
update public.ripening_rules r set is_active=false
from ranked where ranked.id=r.id and ranked.position>1;

alter table public.ripening_rules
  drop constraint ripening_rules_harvest_year_harvest_month_variety_id_key;
create unique index ripening_rules_active_month_variety_key
  on public.ripening_rules(harvest_month,variety_id) where is_active;

create or replace function private.master_validate(
  function_name_value text,master_type_value text,input jsonb,current_row jsonb
)
returns jsonb language plpgsql set search_path='' as $$
declare result jsonb; key text; value numeric; m bigint; v uuid;
begin
  if master_type_value<>'ripening_rule' then
    return private.master_validate_before_s3(function_name_value,master_type_value,input,current_row);
  end if;
  if input ? 'harvest_year' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','追熟マスターに収穫年度は指定しません。',
      jsonb_build_object('field','harvest_year','reason','unsupported'));
  end if;
  m:=private.rpc_input_positive_int(input,'harvest_month',function_name_value='master_register');
  v:=private.rpc_input_uuid(input,'variety_id',function_name_value='master_register');
  if function_name_value='master_register' then
    if m not between 1 and 12 then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫月が範囲外です。',
        jsonb_build_object('field','harvest_month','reason','out_of_range'));
    end if;
    perform private.master_require_active_parent(master_type_value,'variety',v,'variety_id');
  elsif (m is not null and m<>(current_row->>'harvest_month')::bigint)
    or (v is not null and v<>(current_row->>'variety_id')::uuid) then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫月・品種は変更できません。');
  end if;
  result:=case when function_name_value='master_register'
    then jsonb_build_object('harvest_year',2000,'harvest_month',m,'variety_id',v)
    else '{}'::jsonb end;
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

create or replace function private.master_check_duplicates(master_type_value text,effective_row jsonb,exclude_id uuid)
returns void language plpgsql set search_path='' as $$
declare r public.ripening_rules%rowtype;
begin
  if master_type_value<>'ripening_rule' then
    perform private.master_check_duplicates_before_s3(master_type_value,effective_row,exclude_id); return;
  end if;
  select * into r from public.ripening_rules
    where harvest_month=(effective_row->>'harvest_month')::int
      and variety_id=(effective_row->>'variety_id')::uuid and is_active
      and (exclude_id is null or id<>exclude_id);
  if found then
    perform private.rpc_fail('KW400','MASTER_DUPLICATE','同じ収穫月・品種の有効な追熟マスターがあります。',
      jsonb_build_object('field','variety_id','reason','duplicate','existing',jsonb_build_object('master_id',r.id,'is_active',r.is_active)));
  end if;
end;
$$;

drop function public.ripening_inventory_available();
create function public.ripening_inventory_available()
returns table(container_id uuid,display_id text,variety_id uuid,grade_id uuid,
  harvest_month smallint,current_weight_kg numeric,reserved_weight_kg numeric,available_weight_kg numeric)
language sql stable security invoker set search_path='' as $$
  select c.id,c.display_id,c.variety_id,c.grade_id,
    extract(month from receiving.received_on)::smallint,
    c.current_weight_kg::numeric,c.reserved_weight_kg::numeric,
    (c.current_weight_kg-c.reserved_weight_kg)::numeric
  from public.containers c
  join public.sorting_results sorting on sorting.id=c.sorting_result_id
  join public.receiving_lots receiving on receiving.id=sorting.receiving_lot_id
  where c.status='cold_storage' order by c.display_id,c.id;
$$;
revoke all on function public.ripening_inventory_available() from public,anon;
grant execute on function public.ripening_inventory_available() to authenticated,service_role;

-- 既存の未着手計画は、予約元が同一月なら現在の有効マスターで補完する。
with source_months as (
  select l.id,min(extract(month from receiving.received_on))::smallint as harvest_month
  from public.ripening_lots l
  join public.inventory_reservations reservation on reservation.ripening_lot_id=l.id
  join public.containers c on c.id=reservation.container_id
  join public.sorting_results sorting on sorting.id=c.sorting_result_id
  join public.receiving_lots receiving on receiving.id=sorting.receiving_lot_id
  where not (l.master_snapshot ? 'best_before_days')
    and not exists(select 1 from public.ripening_work_results work where work.ripening_lot_id=l.id)
  group by l.id having count(distinct extract(month from receiving.received_on))=1
), matches as (
  select source.id,source.harvest_month,to_jsonb(rule)-'created_by'-'updated_by'-'created_at'-'updated_at' as snapshot
  from source_months source
  join public.ripening_lots lot on lot.id=source.id
  join public.ripening_rules rule on rule.harvest_month=source.harvest_month
    and rule.variety_id=lot.variety_id and rule.is_active
)
update public.ripening_lots lot set
  harvest_year=2000,harvest_month=matches.harvest_month,master_snapshot=matches.snapshot,
  planned_completion_at=lot.planned_ethylene_at
    +(matches.snapshot->>'ethylene_hours')::numeric*interval '1 hour'
    +(matches.snapshot->>'rest_days')::numeric*interval '24 hours'
from matches where matches.id=lot.id;

create or replace function private.ripening_plan_action(fn text,input_value jsonb,actor uuid,correlation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; lot public.ripening_lots%rowtype; previous public.ripening_lots%rowtype;
  m smallint; month_count int; rule public.ripening_rules%rowtype; snap jsonb;
begin
  perform pg_advisory_xact_lock(53,0);
  if input_value ? 'harvest_year' or input_value ? 'harvest_month' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫年月は対象在庫から自動判定します。');
  end if;
  if fn<>'ripening_plan_register' then
    select * into previous from public.ripening_lots
      where id=private.rpc_input_uuid(input_value,'ripening_lot_id',true) for update;
  end if;
  result:=private.ripening_plan_action_before_deadlines(fn,input_value,actor,correlation);
  select * into lot from public.ripening_lots where id=(result->>'id')::uuid;

  if fn in ('ripening_plan_register','ripening_plan_update') then
    select count(distinct extract(month from receiving.received_on)),
      min(extract(month from receiving.received_on))::smallint
    into month_count,m
    from public.inventory_reservations reservation
    join public.containers c on c.id=reservation.container_id
    join public.sorting_results sorting on sorting.id=c.sorting_result_id
    join public.receiving_lots receiving on receiving.id=sorting.receiving_lot_id
    where reservation.ripening_lot_id=lot.id;
    -- 下書きRPCは予約未入力も許容する。確定時にはマスター設定を必須にする。
    if month_count=0 then
      return result;
    elsif month_count<>1 then
      perform private.rpc_fail('KW400','VALIDATION_FAILED','収穫月が異なる在庫を同じ追熟計画に含めることはできません。');
    end if;
    if previous.harvest_month=m and previous.variety_id=lot.variety_id
      and previous.master_snapshot ? 'best_before_days' then
      snap:=previous.master_snapshot;
    else
      select * into rule from public.ripening_rules
        where harvest_month=m and variety_id=lot.variety_id and is_active for share;
      if not found then
        perform private.rpc_fail('KW400','RIPENING_MASTER_NOT_FOUND',
          '品種・収穫月に一致する有効な追熟マスターがありません。');
      end if;
      snap:=to_jsonb(rule)-'created_by'-'updated_by'-'created_at'-'updated_at';
    end if;
    update public.ripening_lots set harvest_year=2000,harvest_month=m,master_snapshot=snap,
      planned_completion_at=planned_ethylene_at
        +(snap->>'ethylene_hours')::numeric*interval '1 hour'
        +(snap->>'rest_days')::numeric*interval '24 hours',updated_by=actor
      where id=lot.id;
    perform private.project_ripening_tasks(lot.id,actor,'品種・収穫月別の追熟予定計算',correlation);
  elsif fn='ripening_plan_confirm' and
    (lot.harvest_month is null or not (lot.master_snapshot ? 'best_before_days')) then
    perform private.rpc_fail('KW400','RIPENING_MASTER_NOT_FOUND',
      '品種・収穫月に一致する追熟マスターを計画に設定してください。');
  end if;
  return public.ripening_plan_get(lot.id);
end;
$$;

-- 補完した計画の表示期限と作業予定を再計算する。
do $$
declare target record;
begin
  for target in select id from public.ripening_lots
    where harvest_month is not null and master_snapshot ? 'best_before_days'
      and not exists(select 1 from public.ripening_work_results work where work.ripening_lot_id=ripening_lots.id)
  loop
    perform private.project_ripening_tasks(target.id,null,'品種・収穫月への追熟条件移行',gen_random_uuid());
  end loop;
end;
$$;

-- 互換列 harvest_year は追熟マスターのCSVには公開しない。
alter function private.csv_master_search_text(text,jsonb) rename to csv_master_search_text_with_ripening_year;
create function private.csv_master_search_text(master_type_value text,row_value jsonb)
returns text language plpgsql stable set search_path='' as $$
declare result_value text;
begin
  if master_type_value<>'ripening_rule' then
    return private.csv_master_search_text_with_ripening_year(master_type_value,row_value);
  end if;
  result_value:=concat_ws(' ',row_value->>'harvest_month',row_value->>'variety_id',
    row_value->>'ethylene_temperature',row_value->>'ethylene_hours',
    row_value->>'rest_temperature',row_value->>'rest_days',
    row_value->>'shippable_days',row_value->>'best_before_days');
  select concat_ws(' ',result_value,variety.code,variety.name) into result_value
    from public.varieties variety where variety.id=(row_value->>'variety_id')::uuid;
  return coalesce(result_value,'');
end;
$$;

alter function private.csv_master_header(text) rename to csv_master_header_with_ripening_year;
create function private.csv_master_header(master_type_value text)
returns text language sql immutable set search_path='' as $$
  select case when master_type_value='ripening_rule'
    then '"内部ID","収穫月","品種内部ID","エチレン処理温度","エチレン処理時間","寝かせ温度","寝かせ日数","出荷可能日数","賞味期限日数","有効","バージョン","更新日時JST"'
    else private.csv_master_header_with_ripening_year(master_type_value) end;
$$;

alter function private.csv_master_row(text,jsonb) rename to csv_master_row_with_ripening_year;
create function private.csv_master_row(master_type_value text,row_value jsonb)
returns text language plpgsql stable set search_path='' as $$
declare cells text[];
begin
  if master_type_value<>'ripening_rule' then
    return private.csv_master_row_with_ripening_year(master_type_value,row_value);
  end if;
  cells:=array[
    private.csv_cell(row_value->>'id',false),
    private.csv_cell(row_value->>'harvest_month',false),
    private.csv_cell(row_value->>'variety_id',false),
    private.csv_cell(row_value->>'ethylene_temperature',false),
    private.csv_cell(row_value->>'ethylene_hours',false),
    private.csv_cell(row_value->>'rest_temperature',false),
    private.csv_cell(row_value->>'rest_days',false),
    private.csv_cell(row_value->>'shippable_days',false),
    private.csv_cell(row_value->>'best_before_days',false),
    private.csv_cell(row_value->>'is_active',false),
    private.csv_cell(row_value->>'version',false),
    private.csv_cell(private.csv_timestamp_jst((row_value->>'updated_at')::timestamptz),false)
  ];
  return array_to_string(cells,',');
end;
$$;

commit;
