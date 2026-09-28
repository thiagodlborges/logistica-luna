# Logística de Entregas — Luna Gelato

Módulo de gestão logística de entregas: painel de monitoramento, cadastro de veículos e programação de rotas por veículo, com integração ao Google Maps.

Faz parte da suíte de sistemas da Luna Gelato (mesmo backend Supabase de [`pedidosacessofabrica`](https://github.com/thiagodlborges/pedidosacessofabrica) e [`freezers-luna`](https://github.com/thiagodlborges/freezers-luna)).

## O que o módulo faz

- **Painel de monitoramento**: rotas do dia, progresso de entregas, veículos ativos e mapa das paradas pendentes.
- **Cadastro de veículos**: placa, modelo, tipo, capacidade, motorista padrão e status.
- **Programação por veículo**: cria rotas (veículo + data + motorista) e adiciona paradas de entrega em sequência.
- **Demanda de entrega**: puxa automaticamente
  - pedidos com status **"Separado"** do módulo [Pedidos — Fábrica](https://github.com/thiagodlborges/pedidosacessofabrica);
  - freezers ativos do módulo [Freezers Externos](https://github.com/thiagodlborges/freezers-luna), priorizando os que estão há mais tempo sem reposição.
- **Integração com Google Maps**: abre a rota completa (todas as paradas) direto no Google Maps, sem precisar de chave de API. Opcionalmente, é possível configurar uma API Key do Google Maps (aba "Config") para exibir um mapa incorporado no painel de monitoramento.
- **Sincronização automática de status**: ao confirmar a entrega de uma parada vinculada a um pedido, o pedido correspondente em "Pedidos — Fábrica" é automaticamente marcado como **"Enviado"** (o mesmo gatilho que já baixa o estoque da Fábrica continua valendo). Ao iniciar a rota, o pedido passa para **"Em transporte"**.

## Stack

Página única (`index.html`), sem build — HTML + CSS + JavaScript puro, usando [`@supabase/supabase-js`](https://supabase.com/docs/reference/javascript) direto via CDN, compartilhando o mesmo projeto Supabase dos demais módulos.

## Acesso

Usuários com perfil `master` têm acesso automático. Outros perfis precisam de uma liberação em `perfil_acessos` com `sistema_slug = 'logistica'`.
