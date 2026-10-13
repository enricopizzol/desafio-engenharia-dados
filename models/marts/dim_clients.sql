{#- Uma linha por cliente, incluindo quem nunca operou (C11 a C25).
    Cadastro vem do staging; métricas de atividade vêm da fato (D22). -#}
with clients as (

    select * from {{ ref('stg_clients') }}

),

activity as (

    -- resumo de atividade por cliente
    select
        client_id,
        min(transaction_date) as first_transaction_date,
        max(transaction_date) as last_transaction_date,
        count(*)              as total_transactions
    from {{ ref('fact_transactions') }}
    group by client_id

)

select
    clients.client_id,
    clients.client_name,
    clients.city,
    clients.state,
    clients.client_created_date,
    activity.first_transaction_date,
    activity.last_transaction_date,
    coalesce(activity.total_transactions, 0) as total_transactions,  -- 0 para quem nunca operou
    activity.client_id is not null           as has_transactions
from clients
left join activity  -- left join mantém os 15 clientes sem transação
    on clients.client_id = activity.client_id
