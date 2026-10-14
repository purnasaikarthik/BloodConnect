-- Alternative to the dashboard "Database Webhooks" screen.
-- Calls your Google Apps Script web app whenever a blood request is added.
-- Replace YOUR_WEB_APP_URL and YOUR_SECRET, then run once in the SQL Editor.

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_new_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'YOUR_WEB_APP_URL?key=YOUR_SECRET',
    body := jsonb_build_object('type', 'INSERT', 'table', 'requests', 'record', to_jsonb(new)),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );
  return new;
end $$;

drop trigger if exists on_request_notify on public.requests;
create trigger on_request_notify after insert on public.requests
  for each row execute function public.notify_new_request();

-- To see whether the call worked after a test request:
-- select id, status_code, content, created from net._http_response order by created desc limit 5;
