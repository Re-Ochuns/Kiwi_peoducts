begin;

alter table public.ripening_work_results
  alter column actual_temperature drop not null;

create or replace function private.ripening_work_temperature(input_value jsonb, field_name text)
returns numeric language plpgsql set search_path = '' as $$
declare value numeric;
begin
  if field_name = 'actual_temperature' and not (input_value ? field_name) then
    return null;
  end if;
  if jsonb_typeof(input_value->field_name) is distinct from 'number' then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','温度を数値で指定してください。',
      jsonb_build_object('field',field_name,'reason','invalid_type'));
  end if;
  value := (input_value->>field_name)::numeric;
  if value <= '-Infinity'::numeric or value >= 'Infinity'::numeric then
    perform private.rpc_fail('KW400','VALIDATION_FAILED','有限の温度を指定してください。');
  end if;
  return value;
end;
$$;

commit;
