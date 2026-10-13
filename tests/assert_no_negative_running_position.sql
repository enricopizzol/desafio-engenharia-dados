{#- Extensão (D17): a posição acumulada não pode ficar negativa em nenhum
    momento, mesmo que depois se recomponha (venda a descoberto). Pega casos
    que o teste da posição final não vê, como C2 VALE3 em T033.
    Severidade própria, warn por padrão. -#}
{{ config(severity = var('negative_running_position_severity')) }}

select
    transaction_id,
    client_id,
    asset_ticker,
    transaction_date,
    operation_type,
    quantity,
    running_quantity
from {{ ref('int_transactions') }}
where running_quantity < 0
