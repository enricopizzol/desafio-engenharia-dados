{#- Bônus 6: incremental (D13).

    - Janela de reprocessamento (>= max - N dias), não `>`: uma transação que
      chega atrasada com data já carregada não se perde.
    - unique_key + delete+insert torna o reprocessamento idempotente.
    - Estratégia trocável por var: delete+insert (padrão) | merge | append.
      append ignora unique_key e duplica a janela; existe só para comparação. -#}
{%- set strategy = var('fact_incremental_strategy') -%}

{{ config(
    materialized = 'incremental',
    unique_key = none if strategy == 'append' else 'transaction_id',
    incremental_strategy = strategy,
    on_schema_change = 'fail'
) }}

select
    transaction_id,
    client_id,
    asset_ticker,
    operation_type,
    transaction_date,
    quantity,
    signed_quantity,
    unit_price,
    gross_amount,
    signed_amount,
    is_possible_duplicate
from {{ ref('int_transactions') }}

{% if is_incremental() %}
where transaction_date >= (
    select {{ dbt.dateadd('day', -1 * var('fact_lookback_days') | int, 'max(transaction_date)') }}
    from {{ this }}
)
{% endif %}
