-- Propostas de freezer ainda não efetivadas entram no backlog de entregas da Logística e podem ser
-- programadas no calendário, mas nunca concluídas (entregue) enquanto não forem efetivadas no módulo Freezers.
-- Já aplicado no Supabase em 28/10/2026.

alter table logistica_entregas add column proposta_pendente boolean not null default false;

create or replace function fn_logistica_sync_proposta() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if new.pedido_tirado is true and new.status_venda = 'proposta' then
    insert into logistica_entregas (tipo, freezer_id, freezer_codigo, freezer_rede, destino_nome, destino_endereco, destino_cidade, latitude, longitude,
                                    status, visita_id, valor_venda, observacoes, proposta_pendente)
    select 'freezer', f.id, f.codigo, f.rede, f.ponto_venda, f.endereco, f.cidade, f.latitude, f.longitude, 'pendente', new.id,
           coalesce((select sum(i.quantidade * i.valor_unitario) from freezer_visita_itens i where i.visita_id = new.id), 0),
           'Proposta de ' || to_char(new.data_visita, 'DD/MM/YYYY') || ' — ainda não efetivada no módulo Freezers', true
    from freezers f where f.id = new.freezer_id
    on conflict (visita_id) where visita_id is not null do nothing;
  elsif tg_op = 'UPDATE' and new.pedido_tirado is false and old.pedido_tirado is true and new.status_venda = 'proposta' then
    delete from logistica_entregas where visita_id = new.id and proposta_pendente and status in ('pendente','programada');
  end if;
  return new;
end $f$;
create trigger trg_logistica_sync_proposta after insert or update of pedido_tirado, status_venda on freezer_visitas
  for each row execute function fn_logistica_sync_proposta();

create or replace function fn_logistica_valor_proposta() returns trigger language plpgsql security definer set search_path = public as $f$
declare v uuid := coalesce(new.visita_id, old.visita_id);
begin
  update logistica_entregas set valor_venda = coalesce((select sum(i.quantidade * i.valor_unitario) from freezer_visita_itens i where i.visita_id = v), 0)
   where visita_id = v and proposta_pendente;
  return coalesce(new, old);
end $f$;
create trigger trg_logistica_valor_proposta after insert or update or delete on freezer_visita_itens
  for each row execute function fn_logistica_valor_proposta();

create or replace function fn_logistica_apaga_entrega_visita() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  delete from logistica_entregas where visita_id = old.id and status <> 'entregue';
  return old;
end $f$;
create trigger trg_logistica_apaga_entrega_visita before delete on freezer_visitas
  for each row execute function fn_logistica_apaga_entrega_visita();

create or replace function fn_logistica_bloqueia_entrega_sem_efetivar() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if new.tipo = 'freezer' and new.visita_id is not null and new.status = 'entregue' and old.status is distinct from 'entregue' then
    if (select status_venda from freezer_visitas where id = new.visita_id) is distinct from 'efetivada' then
      raise exception 'Esta proposta ainda não foi efetivada no módulo de Freezers — ela pode ser programada, mas só pode ser concluída na logística depois de efetivada.';
    end if;
  end if;
  return new;
end $f$;
create trigger trg_logistica_bloqueia_entrega_sem_efetivar before update of status on logistica_entregas
  for each row execute function fn_logistica_bloqueia_entrega_sem_efetivar();

-- efetivar_venda_freezer: o "on conflict (visita_id) ... do nothing" passou a atualizar a entrega existente
--   (valor_venda, observacoes, proposta_pendente = false) enquanto ela não estiver entregue/cancelada.
-- logistica_confirmar_entrega_freezer: recusa venda não efetivada.
-- logistica_info_venda_freezer: devolve também 'efetivada' (boolean).
