# Logística de Entregas — Luna Gelato

Módulo de gestão logística de entregas: painel de monitoramento, cadastro de veículos e programação de rotas por veículo, com integração ao Google Maps.

Faz parte da suíte de sistemas da Luna Gelato (mesmo backend Supabase de [`pedidosacessofabrica`](https://github.com/thiagodlborges/pedidosacessofabrica) e [`freezers-luna`](https://github.com/thiagodlborges/freezers-luna)).

## O que o módulo faz

- **Painel de monitoramento**: rotas do dia, progresso de entregas, veículos ativos e mapa das paradas pendentes.
- **Cadastro de veículos**: placa, modelo, tipo, capacidade, motorista padrão e status.
- **Programação por veículo**: cria rotas (veículo + data + motorista) e adiciona paradas de entrega em sequência.
- **Demanda de entrega** (aba "Demanda de Entrega"): puxa automaticamente
  - pedidos do módulo [Pedidos — Fábrica](https://github.com/thiagodlborges/pedidosacessofabrica) com status **Aprovado** (após o gestor comercial), **Separado** ou **Em transporte**; ficam pendentes até o status virar **Enviado**;
  - a última **proposta** (com itens) de cada freezer ativo do módulo [Freezers Externos](https://github.com/thiagodlborges/freezers-luna), pendente até a entrega ser confirmada (`freezers.ultima_entrega_em` passa a ser posterior à proposta).
  Pedidos aparecem agrupados por prazo (atrasados/hoje/próximos) e propostas por cidade.
- **Sugestão de rotas**: agrupa a demanda por proximidade respeitando "entregas por dia", prioriza pelo prazo (pedido: data prevista; proposta: data da proposta), ordena as paradas pelo menor trajeto (vizinho mais próximo + 2-opt, saindo da fábrica) e permite criar a rota com um clique. Sem custo: o cálculo é feito no navegador.
- **Google Maps sem chave de API**: cada sugestão/rota abre no Google Maps em modo navegação por link (até 10 paradas por link). O mapa do painel usa Leaflet + OpenStreetMap e a busca de endereço usa o Nominatim; nenhum exige chave nem cobrança.
- **Localização de lojas**: pedidos só trazem o nome da loja. O botão "📍 Localização" salva endereço/coordenadas (em `logistica_config`, chave `destino:loja:<nome>`), valendo para todos os pedidos da loja. O ponto de partida (fábrica) é configurado na aba Config.
- **Sincronização automática de status**: ao confirmar a entrega de uma parada vinculada a um pedido, o pedido correspondente em "Pedidos — Fábrica" é automaticamente marcado como **"Enviado"** (o mesmo gatilho que já baixa o estoque da Fábrica continua valendo). Ao iniciar a rota, o pedido passa para **"Em transporte"**.

## Stack

Página única (`index.html`), sem build — HTML + CSS + JavaScript puro, usando [`@supabase/supabase-js`](https://supabase.com/docs/reference/javascript) direto via CDN, compartilhando o mesmo projeto Supabase dos demais módulos.

## Acesso

Usuários com perfil `master` têm acesso automático. Outros perfis precisam de uma liberação em `perfil_acessos` com `sistema_slug = 'logistica'`.

## Banco de dados

`supabase/migrations/20260929_logistica_demanda.sql` cria as funções `logistica_demanda_pedidos()` e `logistica_demanda_freezers()` (SECURITY DEFINER, restritas a master/acesso `logistica`). Elas permitem que usuários só com acesso à Logística vejam a demanda apesar da RLS dos módulos de origem. Enquanto a migração não for aplicada, o módulo cai automaticamente para consultas diretas (funciona para quem também tem acesso a Pedidos e Freezers).
