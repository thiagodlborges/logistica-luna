-- Freezers: parcelamento/vencimentos passam a ser definidos na LOGÍSTICA, no envio.
-- O contas a receber (cobrancas) só é gerado quando a logística confirma a entrega.
-- Rodar uma vez no SQL Editor do Supabase. Vendas já efetivadas antes disto continuam como estão
-- (já têm cobrança gerada) — a confirmação de entrega delas apenas marca como enviada.

alter table freezer_visitas add column if not exists data_envio date;
alter table logistica_entregas add column if not exists valor_venda numeric;

-- 1) Efetivar venda: NÃO exige parcelas e NÃO gera cobrança; encaminha para a logística.
create or replace function public.efetivar_venda_freezer(
  p_visita_id uuid, p_numero_nota text, p_forma_pagamento text, p_parcelas jsonb,
  p_desconto_tipo text default null, p_desconto_valor numeric default null, p_desconto_motivo text default null)
returns bigint
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_freezer_id uuid; v_data_visita date; v_pedido_tirado boolean; v_status_atual text;
  v_valor_bruto numeric; v_valor_desconto numeric := 0; v_valor_liquido numeric;
  v_desconto_tipo text := null; v_desconto_informado numeric := null;
  v_fz freezers%rowtype;
begin
  select freezer_id, data_visita, pedido_tirado, status_venda
    into v_freezer_id, v_data_visita, v_pedido_tirado, v_status_atual
  from freezer_visitas where id = p_visita_id;

  if v_freezer_id is null then raise exception 'Visita/proposta não encontrada.'; end if;
  if not tem_acesso_freezer(v_freezer_id) then raise exception 'Sem acesso a este freezer.'; end if;
  if not v_pedido_tirado then raise exception 'Esta visita não tem pedido — não há o que efetivar.'; end if;
  if v_status_atual = 'efetivada' then raise exception 'Esta proposta já foi efetivada.'; end if;

  select round(coalesce(sum(quantidade * valor_unitario), 0), 2) into v_valor_bruto
  from freezer_visita_itens where visita_id = p_visita_id;

  if p_desconto_tipo is not null and coalesce(p_desconto_valor, 0) <> 0 then
    if p_desconto_tipo = 'percentual' then
      if p_desconto_valor < 0 or p_desconto_valor > 100 then
        raise exception 'Desconto percentual precisa estar entre 0%% e 100%%.';
      end if;
      v_valor_desconto := round(v_valor_bruto * p_desconto_valor / 100, 2);
    elsif p_desconto_tipo = 'valor' then
      if p_desconto_valor < 0 or p_desconto_valor > v_valor_bruto then
        raise exception 'Desconto em R$ não pode ser negativo nem maior que o valor da venda.';
      end if;
      v_valor_desconto := round(p_desconto_valor, 2);
    else
      raise exception 'Tipo de desconto inválido (use percentual ou valor).';
    end if;
    v_desconto_tipo := p_desconto_tipo;
    v_desconto_informado := p_desconto_valor;
  end if;

  v_valor_liquido := v_valor_bruto - v_valor_desconto;
  if v_valor_liquido <= 0 then raise exception 'O valor líquido da venda precisa ser maior que zero.'; end if;

  select * into v_fz from freezers where id = v_freezer_id;

  update freezer_visitas set
    status_venda = 'efetivada',
    numero_nota = nullif(trim(coalesce(p_numero_nota,'')),''),
    forma_pagamento = p_forma_pagamento,
    parcelas = null,
    data_efetivacao = now(),
    efetivado_por = auth.uid(),
    desconto_tipo = v_desconto_tipo,
    desconto_informado = v_desconto_informado,
    desconto_motivo = nullif(trim(coalesce(p_desconto_motivo,'')),''),
    valor_bruto = v_valor_bruto,
    valor_desconto = v_valor_desconto,
    valor_liquido = v_valor_liquido
  where id = p_visita_id;

  insert into logistica_entregas (tipo, freezer_id, freezer_codigo, freezer_rede, destino_nome, destino_endereco,
                                  destino_cidade, latitude, longitude, status, visita_id, valor_venda, observacoes)
  values ('freezer', v_freezer_id, v_fz.codigo, v_fz.rede, v_fz.ponto_venda, v_fz.endereco,
          v_fz.cidade, v_fz.latitude, v_fz.longitude, 'pendente', p_visita_id, v_valor_liquido,
          'Venda efetivada em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
          || ' — R$ ' || replace(to_char(v_valor_liquido, 'FM999999990.00'), '.', ',')
          || coalesce(' — NF ' || nullif(trim(coalesce(p_numero_nota,'')),''), ''))
  on conflict (visita_id) where visita_id is not null do nothing;

  return null;
end;
$function$;

-- 2) Dados da venda para o modal de entrega da logística
create or replace function public.logistica_info_venda_freezer(p_entrega_id uuid) returns jsonb
language plpgsql security definer set search_path to 'public' as $f$
declare e logistica_entregas%rowtype; v freezer_visitas%rowtype;
begin
  if not (is_master() or tem_acesso('logistica')) then raise exception 'Sem acesso ao módulo de Logística.'; end if;
  select * into e from logistica_entregas where id = p_entrega_id;
  if e.id is null or e.visita_id is null then raise exception 'Entrega não vinculada a uma venda de freezer.'; end if;
  select * into v from freezer_visitas where id = e.visita_id;
  return jsonb_build_object(
    'valor_liquido', v.valor_liquido, 'forma_pagamento', v.forma_pagamento, 'numero_nota', v.numero_nota,
    'ja_tem_cobranca', exists(select 1 from cobrancas where origem_visita_id = v.id));
end;
$f$;
grant execute on function public.logistica_info_venda_freezer(uuid) to authenticated;

-- 3) Confirmar entrega de venda de freezer: marca como entregue e GERA o contas a receber
create or replace function public.logistica_confirmar_entrega_freezer(
  p_entrega_id uuid, p_data_entrega date, p_recebido_por text, p_observacoes text,
  p_forma_pagamento text, p_parcelas jsonb)
returns bigint
language plpgsql security definer set search_path to 'public' as $f$
declare
  e logistica_entregas%rowtype; v freezer_visitas%rowtype; fz freezers%rowtype;
  v_data date; v_forma text; v_soma numeric; v_parcelas_norm jsonb; v_primeira date;
  v_cobranca_id bigint := null; v_obs text := null;
begin
  if not (is_master() or tem_acesso('logistica')) then raise exception 'Sem acesso ao módulo de Logística.'; end if;
  select * into e from logistica_entregas where id = p_entrega_id for update;
  if e.id is null then raise exception 'Entrega não encontrada.'; end if;
  if e.tipo <> 'freezer' or e.visita_id is null then raise exception 'Esta entrega não é uma venda de freezer.'; end if;
  if e.status in ('entregue','cancelada') then raise exception 'Esta entrega já foi finalizada.'; end if;

  select * into v from freezer_visitas where id = e.visita_id for update;
  select * into fz from freezers where id = v.freezer_id;
  v_data := coalesce(p_data_entrega, current_date);
  v_forma := coalesce(nullif(trim(coalesce(p_forma_pagamento,'')),''), v.forma_pagamento, 'Boleto');

  if not exists (select 1 from cobrancas where origem_visita_id = v.id) then
    if p_parcelas is null or jsonb_array_length(p_parcelas) = 0 then
      raise exception 'Defina o parcelamento (parcelas e vencimentos) para gerar o contas a receber.';
    end if;
    select coalesce(sum((elem->>'valor')::numeric), 0) into v_soma from jsonb_array_elements(p_parcelas) elem;
    if abs(v_soma - v.valor_liquido) > 0.01 then
      raise exception 'A soma das parcelas (R$ %) não bate com o valor líquido da venda (R$ %).', v_soma, v.valor_liquido;
    end if;
    if exists (select 1 from jsonb_array_elements(p_parcelas) elem where nullif(elem->>'vencimento','') is null) then
      raise exception 'Preencha o vencimento de todas as parcelas.';
    end if;
    if exists (select 1 from jsonb_array_elements(p_parcelas) elem where (elem->>'vencimento')::date < v_data) then
      raise exception 'Nenhum vencimento pode ser anterior à data da entrega.';
    end if;

    select jsonb_agg(jsonb_build_object('num', rn, 'valor', valor, 'valor_recebido', 0, 'forma_pagamento', v_forma,
                                        'data_vencimento', vencimento, 'pago', false, 'situacao', 'Pendente') order by rn)
      into v_parcelas_norm
    from (select row_number() over (order by (elem->>'vencimento')::date, ord) as rn,
                 (elem->>'valor')::numeric as valor, elem->>'vencimento' as vencimento
          from jsonb_array_elements(p_parcelas) with ordinality as t(elem, ord)) o;

    select min((elem->>'vencimento')::date) into v_primeira from jsonb_array_elements(p_parcelas) elem;

    if v.valor_desconto > 0 then
      v_obs := 'Desconto comercial de R$ ' || replace(to_char(v.valor_desconto, 'FM999999990.00'), '.', ',')
        || case when v.desconto_tipo = 'percentual' then ' (' || replace(to_char(v.desconto_informado, 'FM990.00'), '.', ',') || '%)' else '' end
        || ' sobre valor bruto de R$ ' || replace(to_char(v.valor_bruto, 'FM999999990.00'), '.', ',')
        || coalesce(' — ' || v.desconto_motivo, '');
    end if;

    insert into cobrancas (codigo_cliente, nome_cliente, numero_nota, valor_total, forma_pagamento,
                           data_vencimento, status, data_venda, parcelas, origem_visita_id, origem, observacoes)
    values (coalesce(fz.codigo_cliente,'—'), coalesce(fz.razao_social, fz.nome_fantasia, fz.ponto_venda), v.numero_nota,
            v.valor_liquido, v_forma, v_primeira, 'Pendente', v_data, v_parcelas_norm, v.id, 'Freezer Externo', v_obs)
    returning id into v_cobranca_id;

    update freezer_visitas set parcelas = v_parcelas_norm, forma_pagamento = v_forma where id = v.id;
  end if;

  update freezer_visitas set data_envio = v_data where id = v.id;

  update logistica_entregas set status = 'entregue', hora_entrega_real = now(),
         recebido_por = nullif(trim(coalesce(p_recebido_por,'')),''),
         observacoes = nullif(trim(coalesce(observacoes,'') || case when coalesce(trim(p_observacoes),'') <> '' then ' | ' || trim(p_observacoes) else '' end), '')
   where id = p_entrega_id;   -- o gatilho existente atualiza freezers.ultima_entrega_em

  return v_cobranca_id;
end;
$f$;
grant execute on function public.logistica_confirmar_entrega_freezer(uuid, date, text, text, text, jsonb) to authenticated;
