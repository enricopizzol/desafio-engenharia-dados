{{ config(
    materialized = 'incremental',
    unique_key = 'transaction_id',
    incremental_strategy = 'delete+insert',
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
