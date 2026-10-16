-- Chaque nuit (2 h 17 UTC), pg_cron appelle la fonction Edge « account-purge » avec le jeton gardé
-- dans Vault. Sans pg_cron / pg_net (base de test locale), cette migration ne fait rien.
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'pg_cron/pg_net absents : purge nocturne non planifiée';
    return;
  end if;
  execute 'create extension if not exists pg_cron';
  execute 'create extension if not exists pg_net';
  if exists (select 1 from cron.job where jobname = 'covi-account-purge') then
    perform cron.unschedule('covi-account-purge');
  end if;
  perform cron.schedule(
    'covi-account-purge',
    '17 2 * * *',
    $job$
      select net.http_post(
        url := 'https://bmbwmwgfzrijglzcgjut.supabase.co/functions/v1/account-purge',
        headers := pg_catalog.jsonb_build_object(
          'content-type', 'application/json',
          'x-covi-purge-token',
          (select decrypted_secret from vault.decrypted_secrets
           where name = 'covi_account_purge_token')),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000)
    $job$);
end $$;
