{#- Uma linha por cliente, mantendo o registro mais completo (D10). -#}
with source as (

    select * from {{ ref('clients') }}

),

renamed as (

    select
        upper({{ clean_string('client_id') }})                      as client_id,
        {{ clean_string('name') }}                                  as client_name,
        {{ clean_string('city') }}                                  as city,
        upper({{ clean_string('state') }})                          as state,
        {{ dbt.safe_cast(clean_string('created_at'), 'date') }}     as client_created_date
    from source

),

valid as (

    select * from renamed where client_id is not null

),

deduplicated as (

    {{ deduplicate(
        'valid',
        'client_id',
        count_nulls(['client_name', 'city', 'state', 'client_created_date'])
            ~ ', client_created_date, client_name, city'
    ) }}

)

select
    client_id,
    client_name,
    city,
    state,
    client_created_date
from deduplicated
