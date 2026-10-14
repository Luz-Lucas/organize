-- Séries de eventos: as ocorrências continuam sendo linhas de `events`; o
-- `series_id` agrupa as da mesma série e `recurrence` guarda (só para
-- informação) a regra usada para gerá-las.
-- {"freq":"daily|weekdays|weekly|biweekly|monthly","days":[1..7],"until":"YYYY-MM-DD"|null,"count":int|null}

alter table public.events
  add column series_id uuid,
  add column recurrence jsonb check (recurrence is null or jsonb_typeof(recurrence) = 'object');

create index events_series_idx on public.events (user_id, series_id, starts_at) where series_id is not null;

-- Agrupa os eventos importados que já são ocorrências da mesma série:
--   google: external_id "<base>_<instante>"  -> chave = <base>;
--   plano:  external_id "<base>:<data>" ou "<base>:<data>:<código>"
--           -> chave = o external_id sem o trecho da data
--           ("estudo:2026-10-12:C03" -> "estudo:C03"; "np:2026-10-12" -> "np").
-- Só vira série a chave com 2 ou mais linhas do mesmo usuário e da mesma fonte,
-- com o mesmo título e o mesmo horário local de início (America/Sao_Paulo);
-- assim provas "prova:<data>:<código>" com títulos diferentes não se juntam.
-- O id é determinístico (md5), então rodar de novo dá o mesmo resultado.
create or replace function public.backfill_event_series()
returns void
language sql
set search_path = ''
as $$
  with base as (
    select id, user_id, source, title,
           (starts_at at time zone 'America/Sao_Paulo')::time as local_start,
           case
             when source = 'google' and external_id like '%\_%' then split_part(external_id, '_', 1)
             when source = 'plano' and external_id like '%:%'
               then regexp_replace(external_id, ':\d{4}-\d{2}-\d{2}', '')
           end as b
      from public.events
     where series_id is null and external_id is not null
  ), grp as (
    select user_id, source, b
      from base
     where b is not null
     group by user_id, source, b
    having count(*) >= 2
       and count(distinct title) = 1
       and count(distinct local_start) = 1
  )
  update public.events e
     set series_id = md5(g.user_id::text || g.source || g.b)::uuid
    from base x
    join grp g on g.user_id = x.user_id and g.source = x.source and g.b = x.b
   where e.id = x.id;
$$;

revoke all on function public.backfill_event_series() from public, anon, authenticated;

select public.backfill_event_series();
