-- PRÉPRODUCTION UNIQUEMENT — remplace 20261015161000_account_purge_schedule.sql.
-- La version de production programme un appel nocturne vers l'adresse de la production : interdit ici.
-- Sur la préproduction, aucune tâche planifiée ; on retire celle qui existerait par erreur.
-- cron.job n'est lu qu'en SQL dynamique : sans pg_cron (projet neuf), la table n'existe pas et
-- PL/pgSQL refuserait la requête même derrière un test sur pg_extension.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute 'select cron.unschedule(jobid) from cron.job where jobname = $1'
      using 'covi-account-purge';
  end if;
  raise notice 'préproduction : purge nocturne non planifiée (aucun appel vers la production)';
end $$;
