create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Os segredos ficam no Vault (Task 6): 'news_fetch_url' e 'cron_secret'.
-- Sem eles o job roda, mas a requisição falha sem efeito.
select cron.schedule(
  'news-fetch',
  '*/20 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'news_fetch_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
