{#- Tipagem, padronização e filtro de registros inválidos.
    Registros removidos aqui continuam sinalizados pelos testes do seed. -#}
with source as (

    select * from {{ ref('transactions') }}

),

renamed as (

    -- clean_string: trim + string vazia vira nulo; safe_cast: valor inválido vira nulo
    select
        upper({{ clean_string('transaction_id') }})                       as transaction_id,
        upper({{ clean_string('client_id') }})                            as client_id,
        upper({{ clean_string('asset_ticker') }})                         as asset_ticker,
        upper({{ clean_string('operation') }})                            as operation_type,
        {{ dbt.safe_cast(clean_string('quantity'), 'integer') }}          as quantity,
        {{ dbt.safe_cast(clean_string('unit_price'), 'decimal(18,4)') }}  as unit_price,
        {{ dbt.safe_cast(clean_string('transaction_date'), 'date') }}     as transaction_date
    from source

),

valid as (

    select *
    from renamed
    where transaction_id is not null
      and client_id is not null                 -- T021
      and asset_ticker is not null
      and operation_type in ('BUY', 'SELL')
      and quantity > 0                          -- T037 (BUY de -50)
      and unit_price > 0
      and transaction_date is not null

),

deduplicated as (

    -- deduplicate por transaction_id: hoje não há repetição, mas é a chave
    {{ deduplicate('valid', 'transaction_id', 'transaction_date, client_id') }}

)

select
    transaction_id,
    client_id,
    asset_ticker,
    operation_type,
    quantity,
    unit_price,
    transaction_date
from deduplicated
