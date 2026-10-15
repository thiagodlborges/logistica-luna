-- Rota completa: o gestor marca que a rota de um veículo/dia está fechada
-- (não aceita novas entregas até ser reaberta). Rodar uma vez no SQL Editor do Supabase.
alter table logistica_rotas add column if not exists fechada boolean not null default false;
alter table logistica_rotas add column if not exists fechada_em timestamptz;
alter table logistica_rotas add column if not exists fechada_por text;

create or replace function logistica_fn_bloquear_rota_fechada() returns trigger language plpgsql as $f$
begin
  if NEW.rota_id is not null and (TG_OP = 'INSERT' or NEW.rota_id is distinct from OLD.rota_id)
     and exists (select 1 from logistica_rotas r where r.id = NEW.rota_id and r.fechada) then
    raise exception 'Esta rota está marcada como completa e não aceita novas entregas. Reabra a rota para editar.';
  end if;
  return NEW;
end;
$f$;
drop trigger if exists trg_logistica_bloquear_rota_fechada on logistica_entregas;
create trigger trg_logistica_bloquear_rota_fechada before insert or update of rota_id on logistica_entregas
  for each row execute function logistica_fn_bloquear_rota_fechada();
