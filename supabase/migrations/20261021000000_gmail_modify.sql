-- Marcar e-mails como lidos: o consentimento do Gmail passa a pedir gmail.modify.
-- can_modify diz ao app se a conta conectada já tem esse escopo (gravado pelo servidor a partir de
-- google_accounts.scopes). Contas antigas (só gmail.metadata) ficam false até reconectar.
-- O cliente só lê email_state (sem policy nova): o grant de select da migração do Gmail já cobre a coluna.

alter table public.email_state
  add column can_modify boolean not null default false;

-- Quem já tem o escopo novo gravado fica true desde já.
update public.email_state s
set can_modify = true
from public.google_accounts g
where g.user_id = s.user_id
  and g.provider = 'gmail'
  and g.scopes like '%https://www.googleapis.com/auth/gmail.modify%';
