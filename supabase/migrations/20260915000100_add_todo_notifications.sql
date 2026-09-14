begin;
create table private.todo_notifications (
 id uuid primary key default gen_random_uuid(),
 request_key text not null unique,
 mode text not null check(mode in ('manual','daily')),
 actor_id uuid references public.profiles(id),
 status text not null default 'sending' check(status in ('sending','sent','failed','unknown')),
 error_code text,
 task_count integer,
 created_at timestamptz not null default now(),
 finished_at timestamptz
);
revoke all on private.todo_notifications from public,anon,authenticated;

create function public.todo_notification_begin(key_value text,mode_value text,actor_value uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare row_value private.todo_notifications; today_value date := (now() at time zone 'Asia/Tokyo')::date;
begin
 perform pg_advisory_xact_lock(15092026,1);
 if mode_value not in ('manual','daily') or key_value is null or length(key_value)>100 then
  raise exception 'Invalid notification request';
 end if;
 if mode_value='daily' and (actor_value is not null or key_value <> 'daily:'||today_value::text) then
  raise exception 'Invalid daily request';
 end if;
 if mode_value='manual' and not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id
   where p.id=actor_value and p.access_status='active' and r.role='administrator') then
  raise exception 'Administrator required' using errcode='42501';
 end if;
 select * into row_value from private.todo_notifications where request_key=key_value;
 if found then return jsonb_build_object('claimed',false,'status',row_value.status); end if;
 if mode_value='manual' and exists(select 1 from private.todo_notifications
  where mode='manual' and created_at>now()-interval '1 minute') then
  return jsonb_build_object('claimed',false,'status','rate_limited');
 end if;
 insert into private.todo_notifications(request_key,mode,actor_id) values(key_value,mode_value,actor_value)
 returning * into row_value;
 return jsonb_build_object('claimed',true,'id',row_value.id);
end;
$$;
create function public.todo_notification_finish(id_value uuid,status_value text,count_value integer,error_value text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if status_value not in ('sent','failed','unknown') or error_value is not null and error_value not in
 ('DATA_UNAVAILABLE','DISCORD_REJECTED','DELIVERY_UNKNOWN') then raise exception 'Invalid result'; end if;
 update private.todo_notifications set status=status_value,task_count=count_value,error_code=error_value,finished_at=now()
 where id=id_value and status='sending';
end;
$$;
revoke all on function public.todo_notification_begin(text,text,uuid),public.todo_notification_finish(uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.todo_notification_begin(text,text,uuid),public.todo_notification_finish(uuid,text,integer,text) to service_role;

create function private.dispatch_daily_todo_notification()
returns void language plpgsql security definer set search_path='' as $$
declare worker_url text; worker_token text;
begin
 select decrypted_secret into worker_url from vault.decrypted_secrets where name='todo_notification_url';
 select decrypted_secret into worker_token from vault.decrypted_secrets where name='todo_notification_token';
 if nullif(worker_url,'') is null or nullif(worker_token,'') is null then return; end if;
 if worker_url !~ '^https://[a-z]{20}\.supabase\.co/functions/v1/todo-notify$' then raise exception 'Invalid notification URL'; end if;
 perform net.http_post(url:=worker_url,headers:=jsonb_build_object('Content-Type','application/json',
 'x-todo-notification-token',worker_token),body:='{"mode":"daily"}'::jsonb,timeout_milliseconds:=60000);
end;
$$;
revoke all on function private.dispatch_daily_todo_notification() from public,anon,authenticated;
-- Supabase pg_cron runs in UTC: 23:00 UTC = 08:00 Asia/Tokyo next day.
select cron.schedule('daily-todo-discord','0 23 * * *','select private.dispatch_daily_todo_notification()');
commit;
