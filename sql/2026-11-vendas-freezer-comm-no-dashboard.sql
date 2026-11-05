-- Vendas do Freezer Comm (Loja de Fábrica) nos totais de vendas de freezers.
-- As vendas da Loja de Fábrica nascem da DIFERENÇA DE ESTOQUE das contagens
-- (freezer_lojafab_contagens/_itens: qtd_vendida começa = diferença positiva e é
-- ajustável na confirmação) e não têm visita em freezer_visitas, por isso não
-- apareciam em dashboard_venda_freezers_mes nem em freezer_vendas_do_dia.
-- Passam a entrar contagens "proposta" e "confirmada" (qtd_vendida * preco_unit).
-- Rodar uma vez no SQL Editor do Supabase.

create or replace function public.dashboard_venda_freezers_mes(p_data_inicio date, p_data_fim date)
returns table(valor_total numeric, quantidade_itens numeric, freezers_com_venda bigint)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (is_master() or is_freezers_backoffice() or is_freezers_repositor()) then
    raise exception 'Sem acesso.';
  end if;
  return query
  with vendas as (
    select fvi.quantidade as qtd, fvi.quantidade * fvi.valor_unitario as valor, fv.freezer_id as fid
    from freezer_visita_itens fvi
    join freezer_visitas fv on fv.id = fvi.visita_id
    where fv.data_visita between p_data_inicio and p_data_fim
    union all
    select ci.qtd_vendida, ci.qtd_vendida * coalesce(ci.preco_unit, 0), c.freezer_id
    from freezer_lojafab_contagem_itens ci
    join freezer_lojafab_contagens c on c.id = ci.contagem_id
    where c.data_contagem between p_data_inicio and p_data_fim
      and c.status in ('proposta', 'confirmada')
      and ci.qtd_vendida > 0
  )
  select coalesce(sum(valor), 0), coalesce(sum(qtd), 0), count(distinct fid) from vendas;
end;
$$;

create or replace function public.freezer_vendas_do_dia(p_data date)
returns table(freezer_id uuid, razao_social text, nome_fantasia text, ponto_venda text, codigo_cliente text,
              endereco text, cidade text, produto_nome text, quantidade numeric, unidade text,
              valor_unitario numeric, valor_total numeric)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (is_master() or is_freezers_backoffice() or is_freezers_repositor()) then raise exception 'Sem acesso.'; end if;
  return query
  select f.id, f.razao_social, f.nome_fantasia, f.ponto_venda, f.codigo_cliente, f.endereco, f.cidade,
         i.produto_nome, i.quantidade, i.unidade, i.valor_unitario, (i.quantidade * i.valor_unitario)
  from freezer_visita_itens i
  join freezer_visitas v on v.id = i.visita_id
  join freezers f on f.id = v.freezer_id
  where v.data_visita = p_data
    and (is_master() or is_freezers_backoffice() or f.repositor_id = auth.uid())
  union all
  -- Loja de Fábrica (ex.: Freezer Comm): diferença de estoque = venda (só master/backoffice)
  select lf.id, lf.nome, lf.nome, lf.nome, 'LOJAFAB', null::text, null::text,
         ci.produto_nome, ci.qtd_vendida, 'un', coalesce(ci.preco_unit, 0), ci.qtd_vendida * coalesce(ci.preco_unit, 0)
  from freezer_lojafab_contagem_itens ci
  join freezer_lojafab_contagens c on c.id = ci.contagem_id
  join freezer_lojafab lf on lf.id = c.freezer_id
  where c.data_contagem = p_data
    and c.status in ('proposta', 'confirmada')
    and ci.qtd_vendida > 0
    and (is_master() or is_freezers_backoffice())
  order by 4, 8;
end;
$$;
