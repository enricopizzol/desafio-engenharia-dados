{#- Grão: cliente + ativo, agregado a partir da fact_transactions.
    Posições zeradas e negativas são mantidas e classificadas em
    position_status; o teste assert_no_negative_position lê as negativas.
    Com portfolio_hide_negative_positions = true, as negativas são removidas. -#}
with transactions as (

    select * from {{ ref('fact_transactions') }}

),

aggregated as (

    select
        client_id,
        asset_ticker,
        -- posição líquida em quantidade: BUY − SELL (o teste singular olha esta coluna)
        cast(sum(signed_quantity) as bigint)                                as net_quantity,
        -- posição líquida em valor financeiro: BUY − SELL, em R$ (não é volume, valor de mercado nem lucro)
        cast(sum(signed_amount) as decimal(18,2))                           as net_amount,
        cast(sum(case when operation_type = 'BUY'  then quantity else 0 end) as bigint) as total_bought_quantity,
        cast(sum(case when operation_type = 'SELL' then quantity else 0 end) as bigint) as total_sold_quantity,
        cast(sum(case when operation_type = 'BUY' then gross_amount else 0 end) as decimal(18,2)) as total_bought_amount,
        cast(sum(case when operation_type = 'SELL' then gross_amount else 0 end) as decimal(18,2)) as total_sold_amount,
        min(transaction_date)                                               as first_transaction_date,
        max(transaction_date)                                               as last_transaction_date,
        count(*)                                                            as total_transactions
    from transactions
    group by client_id, asset_ticker

),

final as (

    select
        client_id || '|' || asset_ticker as portfolio_key,
        client_id,
        asset_ticker,
        net_quantity,
        net_amount,
        total_bought_quantity,
        total_sold_quantity,
        total_bought_amount,
        total_sold_amount,
        -- preço médio de compra (só compras entram)
        cast(
            case when total_bought_quantity > 0
                 then total_bought_amount / total_bought_quantity
            end as decimal(18,4)
        ) as avg_buy_price,
        first_transaction_date,
        last_transaction_date,
        total_transactions,
        case
            when net_quantity > 0 then 'open'
            when net_quantity = 0 then 'closed'
            else 'negative'
        end as position_status
    from aggregated

)

select *
from final
{% if var('portfolio_hide_negative_positions') %}
where net_quantity >= 0
{% endif %}
