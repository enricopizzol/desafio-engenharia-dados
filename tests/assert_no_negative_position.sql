{#- Devolve as posições com quantidade líquida negativa (net_quantity < 0)
    no mart_client_portfolio.

    A severidade vem de negative_position_severity (warn por padrão): com
    warn, o dbt test mostra o aviso e grava as linhas no schema de auditoria
    sem sair com erro. Para reprovar:
      dbt test --vars '{negative_position_severity: error}'
    Com severidade error, negative_position_error_if define a partir de
    quantas linhas o teste falha. Ex.: avisa até 10 e falha acima:
      dbt test --vars '{negative_position_severity: error, negative_position_error_if: ">10"}'

    Olha a posição líquida em quantidade (net_quantity), não em valor
    financeiro (net_amount): valor negativo com quantidade positiva é
    legítimo e não indica lucro nem prejuízo. -#}
{{ config(
    severity = var('negative_position_severity'),
    warn_if = var('negative_position_warn_if'),
    error_if = var('negative_position_error_if')
) }}

select
    portfolio_key,
    client_id,
    asset_ticker,
    total_bought_quantity,
    total_sold_quantity,
    net_quantity
from {{ ref('mart_client_portfolio') }}
where net_quantity < 0
