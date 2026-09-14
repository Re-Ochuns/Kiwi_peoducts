begin;

-- Bound one page and retain the existing security-invoker/RLS label contract.
create function public.ripening_labels_get(container_ids uuid[])
returns setof jsonb
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if container_ids is null or cardinality(container_ids) > 50 then
    raise exception using errcode = '22023',
      message = 'container_ids must contain at most 50 IDs';
  end if;
  return query
    select label
    from (select distinct id from unnest(container_ids) as ids(id)) requested
    cross join lateral (select public.ripening_label_get(requested.id) as label) data
    where label is not null;
end;
$$;
revoke all on function public.ripening_labels_get(uuid[]) from public, anon;
grant execute on function public.ripening_labels_get(uuid[]) to authenticated, service_role;

commit;
