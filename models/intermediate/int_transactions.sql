{#- Junta transações e clientes e aplica as regras de negócio.

    D9: T035/T036 são idênticas exceto pelo ID. Por padrão as duas ficam e
    recebem is_possible_duplicate = true. Com
    --vars '{dedup_transactions_by_content: true}' só a de menor ID fica. -#}
with transactions as (

    select * from {{ ref('stg_transactions') }}

),

clients as (

    select * from {{ ref('stg_clients') }}

),

flagged as (

    select
        transactions.*,
        count(*) over (
            partition by client_id, asset_ticker, operation_type,
                         quantity, unit_price, transaction_date
        ) as duplicate_group_size,
        row_number() over (
            partition by client_id, asset_ticker, operation_type,
                         quantity, unit_price, transaction_date
            order by transaction_id
        ) as duplicate_rank
    from transactions

),

kept as (

    select *
    from flagged
    {% if var('dedup_transactions_by_content') %}
    where duplicate_rank = 1
    {% endif %}

),

enriched as (

    select
        kept.transaction_id,
        kept.client_id,
        clients.client_name,
        clients.state as client_state,
        kept.asset_ticker,
        kept.operation_type,
        kept.quantity,
        kept.unit_price,
        kept.transaction_date,

        case kept.operation_type
            when 'BUY' then kept.quantity
            when 'SELL' then -kept.quantity
        end as signed_quantity,

        cast(kept.quantity * kept.unit_price as decimal(18,2)) as gross_amount,

        kept.duplicate_group_size > 1 as is_possible_duplicate
    from kept
    left join clients
        on kept.client_id = clients.client_id

)

select
    *,
    cast(sign(signed_quantity) * gross_amount as decimal(18,2)) as signed_amount,
    sum(signed_quantity) over (
        partition by client_id, asset_ticker
        order by transaction_date, transaction_id
        rows between unbounded preceding and current row
    ) as running_quantity
from enriched
