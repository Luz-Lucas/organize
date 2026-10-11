-- O horário de uma localização é sempre o do servidor: um relógio errado no celular
-- (ou um valor forjado) não pode envelhecer nem adiantar a localização, que decide
-- se o despertar toca ou é pulado por "fora de casa".

create or replace function public.user_locations_set_reported_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.reported_at := now();
  return new;
end;
$$;

create trigger user_locations_reported_at
  before insert or update on public.user_locations
  for each row execute function public.user_locations_set_reported_at();
