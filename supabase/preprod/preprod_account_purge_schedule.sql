-- PRÉPRODUCTION UNIQUEMENT — remplace 20261015161000_account_purge_schedule.sql.
-- La version de production programme un appel nocturne vers l'adresse de la production : interdit ici.
-- Sur la préproduction, aucune tâche planifiée ; on retire celle qui existerait par erreur.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from cron.job where jobname = 'covi-account-purge') then
    perform cron.unschedule('covi-account-purge');
  end if;
  raise notice 'préproduction : purge nocturne non planifiée (aucun appel vers la production)';
end $$;
