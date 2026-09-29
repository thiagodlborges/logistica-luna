-- Demanda de entrega da Logística.
-- Os módulos de origem têm RLS própria (pedidos: pedidos_loja/pedidos_fabrica;
-- freezers: tem_acesso_freezer), então um usuário só com acesso a 'logistica'
-- não enxergaria a demanda. Estas funções expõem apenas o necessário.
-- Migração aditiva: só cria funções; nenhuma tabela é alterada.

-- Pedidos aprovados pelo gestor comercial que ainda não foram enviados.
create or replace function public.logistica_demanda_pedidos()
returns table (
  id integer, numero_pedido text, loja text, data_pedido date,
  data_entrega_prevista date, status text, aprovado_por text, observacoes text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.numero_pedido, p.loja, p.data_pedido,
         p.data_entrega_prevista, p.status, p.aprovado_por, p.observacoes
  from pedidos p
  where (is_master() or tem_acesso('logistica'))
    and p.status in ('aprovado', 'separado', 'em_transporte')
  order by p.data_entrega_prevista nulls last, p.id;
$$;

-- Última proposta (com itens) de cada freezer ativo que ainda não foi entregue.
create or replace function public.logistica_demanda_freezers()
returns table (
  freezer_id uuid, codigo text, ponto_venda text, nome_fantasia text, rede text,
  endereco text, cidade text, latitude numeric, longitude numeric,
  ultima_entrega_em timestamptz, visita_id uuid, data_visita date,
  valor_liquido numeric, qtd_itens bigint
)
language sql stable security definer set search_path = public as $$
  select distinct on (v.freezer_id)
         f.id, f.codigo, f.ponto_venda, f.nome_fantasia, f.rede,
         f.endereco, f.cidade, f.latitude, f.longitude,
         f.ultima_entrega_em, v.id, v.data_visita, v.valor_liquido,
         (select count(*) from freezer_visita_itens i where i.visita_id = v.id)
  from freezer_visitas v
  join freezers f on f.id = v.freezer_id
  where (is_master() or tem_acesso('logistica'))
    and v.status_venda = 'proposta'
    and f.status = 'ativo'
    and exists (select 1 from freezer_visita_itens i where i.visita_id = v.id)
    and (f.ultima_entrega_em is null or f.ultima_entrega_em < v.criado_em)
  order by v.freezer_id, v.data_visita desc, v.criado_em desc;
$$;

revoke all on function public.logistica_demanda_pedidos() from public, anon;
revoke all on function public.logistica_demanda_freezers() from public, anon;
grant execute on function public.logistica_demanda_pedidos() to authenticated;
grant execute on function public.logistica_demanda_freezers() to authenticated;
