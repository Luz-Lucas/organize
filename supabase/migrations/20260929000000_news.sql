create extension if not exists unaccent with schema extensions;

create table public.news_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade, -- null = catálogo
  name text not null check (length(btrim(name)) > 0),
  section text not null default 'Geral',
  feed_url text not null check (feed_url ~ '^https?://'),
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, feed_url)
);

create table public.news_subscriptions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  source_id uuid not null references public.news_sources (id) on delete cascade,
  primary key (user_id, source_id)
);

create table public.news_prefs (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  keywords text[] not null default '{}',
  blocked text[] not null default '{}',
  max_age_hours integer not null default 48 check (max_age_hours between 1 and 336),
  briefing_count integer not null default 3 check (briefing_count between 0 and 10),
  updated_at timestamptz not null default now()
);
create trigger touch_updated_at before update on public.news_prefs
  for each row execute function public.touch_updated_at();

create table public.news_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source_id uuid not null references public.news_sources (id) on delete cascade,
  url text not null,
  title text not null,
  summary text not null default '',
  image_url text,
  published_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  unique (user_id, url)
);
create index news_items_recent_idx on public.news_items (user_id, published_at desc);

alter table public.news_sources enable row level security;
alter table public.news_subscriptions enable row level security;
alter table public.news_prefs enable row level security;
alter table public.news_items enable row level security;

create policy "catálogo ou próprio" on public.news_sources for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy "insere próprio" on public.news_sources for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "altera próprio" on public.news_sources for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "apaga próprio" on public.news_sources for delete to authenticated
  using (user_id = (select auth.uid()));
create policy "dono" on public.news_subscriptions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "dono" on public.news_prefs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "lê próprio" on public.news_items for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.news_term_match(haystack text, term text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select length(btrim(term)) > 0
     and haystack ~ (
       '\m'
       || regexp_replace(
            lower(extensions.unaccent('extensions.unaccent'::regdictionary, btrim(term))),
            '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
       || '\M');
$$;

create or replace function public.news_feed(p_user uuid default auth.uid(), p_limit integer default 50)
returns table (
  id uuid, source_id uuid, source_name text, title text, summary text,
  url text, image_url text, published_at timestamptz, highlighted boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with prefs as (
    select coalesce(p.keywords, '{}') as keywords,
           coalesce(p.blocked, '{}') as blocked,
           coalesce(p.max_age_hours, 48) as max_age
    from (select 1) as one
    left join public.news_prefs p on p.user_id = p_user
  ),
  items as (
    select i.*, s.name as source_name,
           lower(extensions.unaccent('extensions.unaccent'::regdictionary, i.title || ' ' || i.summary)) as haystack
    from public.news_items i
    join public.news_subscriptions sub on sub.source_id = i.source_id and sub.user_id = p_user
    join public.news_sources s on s.id = i.source_id
    where i.user_id = p_user
      and i.published_at >= now() - make_interval(hours => (select max_age from prefs))
  )
  select i.id, i.source_id, i.source_name, i.title, i.summary, i.url, i.image_url, i.published_at,
         exists (select 1 from unnest((select keywords from prefs)) k where public.news_term_match(i.haystack, k)) as highlighted
  from items i
  where not exists (select 1 from unnest((select blocked from prefs)) b where public.news_term_match(i.haystack, b))
  order by highlighted desc, i.published_at desc
  limit p_limit;
$$;

insert into public.news_sources (user_id, name, section, feed_url) values
  (null, 'G1', 'Principais', 'https://g1.globo.com/rss/g1/'),
  (null, 'G1', 'Política', 'https://g1.globo.com/rss/g1/politica/'),
  (null, 'G1', 'Economia', 'https://g1.globo.com/rss/g1/economia/'),
  (null, 'G1', 'Tecnologia', 'https://g1.globo.com/rss/g1/tecnologia/'),
  (null, 'G1', 'Educação', 'https://g1.globo.com/rss/g1/educacao/'),
  (null, 'G1', 'Ciência e Saúde', 'https://g1.globo.com/rss/g1/ciencia-e-saude/'),
  (null, 'Folha de S.Paulo', 'Em cima da hora', 'https://feeds.folha.uol.com.br/emcimadahora/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Poder', 'https://feeds.folha.uol.com.br/poder/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Mercado', 'https://feeds.folha.uol.com.br/mercado/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Tec', 'https://feeds.folha.uol.com.br/tec/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Mundo', 'https://feeds.folha.uol.com.br/mundo/rss091.xml'),
  (null, 'Estadão', 'Política', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/politica/'),
  (null, 'Estadão', 'Economia', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/economia/'),
  (null, 'Estadão', 'Brasil', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/brasil/'),
  (null, 'O Globo', 'Principais', 'https://oglobo.globo.com/rss/oglobo'),
  (null, 'CNN Brasil', 'Principais', 'https://www.cnnbrasil.com.br/feed/'),
  (null, 'BBC News Brasil', 'Principais', 'https://feeds.bbci.co.uk/portuguese/rss.xml'),
  (null, 'Agência Brasil', 'Últimas', 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml');
