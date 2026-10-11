-- Despertar: parar a música depois de N segundos e escolher o que vem depois dela.
alter table public.wake_plans
  add column music_stop_after_sec integer
    constraint wake_plans_music_stop_after_sec_check check (music_stop_after_sec between 5 and 600),
  add column after_music text not null default 'briefing'
    constraint wake_plans_after_music_check check (after_music in ('briefing', 'headlines', 'end'));
