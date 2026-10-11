-- Logística: fluxo simplificado (veículo só com nome, pedido "Enviar p/ Logística", devolução à fábrica)
-- Rodar uma vez no SQL Editor do Supabase (projeto compartilhado dos módulos Luna).

-- 1) Veículos: apenas o nome é obrigatório
alter table logistica_veiculos add column if not exists nome text;
update logistica_veiculos set nome = trim(coalesce(modelo,'') || ' ' || coalesce(placa,'')) where nome is null;
alter table logistica_veiculos alter column nome set not null;
alter table logistica_veiculos alter column placa drop not null;
alter table logistica_veiculos alter column modelo drop not null;

-- 2) Novos status de pedido: em_logistica e devolvido_logistica
alter table pedidos drop constraint if exists pedidos_status_check;
alter table pedidos add constraint pedidos_status_check check (status = any (array[
  'pendente_aprovacao','aprovado','pendente','confirmado','separado','enviado','rejeitado','cancelado',
  'rascunho','em_producao','em_transporte','entregue','em_logistica','devolvido_logistica']));
alter table pedidos add column if not exists logistica_motivo text;

create or replace function bloquear_avanco_pedido_sem_item() returns trigger language plpgsql as $f$
begin
  if NEW.status in ('aprovado','confirmado','separado','em_producao','em_logistica','em_transporte','enviado','entregue') then
    if not exists (select 1 from pedido_itens where pedido_id = NEW.id) then
      raise exception 'Não é possível colocar o pedido em "%": ele não tem nenhum item cadastrado.', NEW.status;
    end if;
  end if;
  return NEW;
end;
$f$;

-- 3) "Enviado" só pode ser definido pelo módulo logístico
create or replace function fn_pedido_enviado_so_logistica() returns trigger language plpgsql as $f$
begin
  if NEW.status = 'enviado' and OLD.status is distinct from 'enviado'
     and coalesce(current_setting('app.via_logistica', true), '') <> '1' then
    raise exception 'O status "Enviado" só pode ser definido pelo módulo de Logística (ao confirmar a entrega). Use "Enviar para Logística".';
  end if;
  return NEW;
end;
$f$;
drop trigger if exists trg_pedido_enviado_so_logistica on pedidos;
create trigger trg_pedido_enviado_so_logistica before update on pedidos
  for each row execute function fn_pedido_enviado_so_logistica();

-- 4) Entrega confirmada na logística => pedido "enviado" (dispara a baixa de estoque já existente)
create or replace function logistica_fn_sync_entrega_status() returns trigger
language plpgsql security definer set search_path to 'public' as $f$
declare v_status text;
begin
  if NEW.status is distinct from OLD.status then
    if NEW.tipo = 'pedido' and NEW.pedido_id is not null then
      if NEW.status = 'entregue' then
        select status into v_status from pedidos where id = NEW.pedido_id;
        if v_status is distinct from 'enviado' then
          if v_status not in ('em_logistica','em_transporte') then
            raise exception 'O pedido não está no setor logístico (status atual: %). Atualize a lista.', v_status;
          end if;
          perform set_config('app.via_logistica', '1', true);
          update pedidos set status = 'enviado' where id = NEW.pedido_id;
          perform set_config('app.via_logistica', '', true);
        end if;
      end if;
    elsif NEW.tipo = 'freezer' and NEW.freezer_id is not null and NEW.status = 'entregue' then
      update freezers set ultima_entrega_em = now() where id = NEW.freezer_id;
    end if;
  end if;
  return NEW;
end;
$f$;

-- 5) Devolver pedido à fábrica (inconsistência detectada no envio)
create or replace function logistica_devolver_pedido(p_pedido_id integer, p_motivo text) returns void
language plpgsql security definer set search_path to 'public' as $f$
declare v_status text;
begin
  if not (is_master() or tem_acesso('logistica')) then raise exception 'Sem acesso ao módulo de Logística.'; end if;
  if coalesce(trim(p_motivo),'') = '' then raise exception 'Informe o motivo da devolução.'; end if;
  select status into v_status from pedidos where id = p_pedido_id for update;
  if v_status is null then raise exception 'Pedido não encontrado.'; end if;
  if v_status not in ('em_logistica','em_transporte') then
    raise exception 'Só é possível devolver pedidos que estão na logística (status atual: %).', v_status;
  end if;
  update logistica_entregas set status = 'cancelada',
         observacoes = trim(coalesce(observacoes,'') || ' [Devolvido à fábrica: ' || p_motivo || ']')
   where pedido_id = p_pedido_id and tipo = 'pedido' and status not in ('entregue','cancelada');
  update pedidos set status = 'devolvido_logistica', logistica_motivo = p_motivo where id = p_pedido_id;
end;
$f$;
grant execute on function logistica_devolver_pedido(integer, text) to authenticated;

-- 6) Logística lê pedidos / itens (escrita só via RPC / gatilhos)
drop policy if exists pedidos_logistica_select on pedidos;
create policy pedidos_logistica_select on pedidos for select using (tem_acesso('logistica'));
drop policy if exists pedido_itens_logistica_select on pedido_itens;
create policy pedido_itens_logistica_select on pedido_itens for select using (tem_acesso('logistica'));

-- 7) Endereço/coordenadas das lojas Luna (preenchido uma vez, usado na roteirização)
create table if not exists logistica_lojas_enderecos (
  loja text primary key,
  endereco text, cidade text, latitude numeric, longitude numeric,
  atualizado_em timestamptz not null default now()
);
alter table logistica_lojas_enderecos enable row level security;
drop policy if exists logistica_lojas_enderecos_all on logistica_lojas_enderecos;
create policy logistica_lojas_enderecos_all on logistica_lojas_enderecos for all
  using (is_master() or tem_acesso('logistica')) with check (is_master() or tem_acesso('logistica'));
