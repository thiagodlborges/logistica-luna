# Logística de Entregas — Luna Gelato

Módulo de gestão logística de entregas: painel de monitoramento, cadastro de veículos e programação de rotas por veículo, com integração ao Google Maps.

Faz parte da suíte de sistemas da Luna Gelato (mesmo backend Supabase de [`pedidosacessofabrica`](https://github.com/thiagodlborges/pedidosacessofabrica) e [`freezers-luna`](https://github.com/thiagodlborges/freezers-luna)).

## O que o módulo faz

- **Grade de Entregas**: grade semanal por **veículo × dia**. Clique numa célula para montar a rota do dia manualmente (adicionar da fila, reordenar ↑↓), **otimizar a ordem** pelo caminho mais curto e abrir a rota no Google Maps. O botão **Sugerir grade** distribui a fila entre os veículos/dias escolhidos agrupando por proximidade geográfica (mesma lógica de roteirização do módulo Freezers); a sugestão só é gravada depois de conferida.
- **Fila de Entrega**: pedidos que a fábrica **enviou para a logística** (status `em_logistica`), freezers ativos, e — só para planejamento — o que ainda está em preparo na fábrica (aprovado/confirmado/separação) e o que foi devolvido para ajuste.
- **Resultado da entrega**: em cada parada o operador marca **✓ Entregue** (o pedido passa a **Enviado** nos dois módulos, com a baixa de estoque) ou **✕ Não entregue** — reprogramar (volta para a fila) ou **devolver à fábrica** por inconsistência (falta de produto etc.).
- **Devolução à fábrica**: o pedido volta ao módulo Pedidos — Fábrica (`devolvido_logistica`, com o motivo) para troca/remoção de itens; depois a fábrica usa **Reenviar p/ Logística** e ele reaparece na fila.
- **Vendas de freezers**: propostas efetivadas no módulo Freezers chegam à fila como "aguardando envio". O **parcelamento e os vencimentos são definidos aqui**, ao confirmar a entrega (prazos em dias contados da data da entrega, ex.: 30/60/90); só então o **contas a receber** (`cobrancas`) é gerado. "Não entregue" devolve a venda à fila sem perdê-la.
- **Veículos**: só o **nome** é obrigatório; placa, modelo, capacidade, motorista etc. são opcionais.
- **Endereços**: endereço de cada loja cadastrado uma vez (coordenadas localizadas pelo Google Maps com a chave da aba Config); usado na grade e na otimização. Opcionalmente, configure o **ponto de saída** (fábrica).
- **Painel**: rotas do dia, progresso e mapa das paradas pendentes.

> O status **Enviado** deixou de ser acionável no módulo Pedidos — Fábrica: o último status editável lá é *Enviar para Setor Logístico*. "Enviado" só é definido aqui, ao confirmar a entrega (garantido por gatilho no banco).

### Banco de dados
Rode `sql/2026-10-logistica-fluxo-simplificado.sql` e `sql/2026-10-freezer-parcelamento-na-logistica.sql` (nessa ordem, uma vez cada) no SQL Editor do Supabase **antes** de publicar esta versão (e a nova versão de `pedidosacessofabrica`). Pedidos já enviados permanecem como `enviado`.

## Stack

Página única (`index.html`), sem build — HTML + CSS + JavaScript puro, usando [`@supabase/supabase-js`](https://supabase.com/docs/reference/javascript) direto via CDN, compartilhando o mesmo projeto Supabase dos demais módulos.

## Acesso

Usuários com perfil `master` têm acesso automático. Outros perfis precisam de uma liberação em `perfil_acessos` com `sistema_slug = 'logistica'`.
