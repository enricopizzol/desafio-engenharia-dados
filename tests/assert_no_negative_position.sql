{#- Teste singular exigido pelo enunciado: nenhum cliente pode terminar com
    quantidade líquida negativa em um ativo.

    D3: severidade warn por padrão, para que `dbt test` detecte (WARN + linhas
    gravadas no schema de auditoria) sem sair com erro. Modo estrito:
      dbt test --vars '{negative_position_severity: error}'
    Alternativa por limiares (só vale com severity error; com warn o dbt
    nunca avalia error_if). Ex.: avisa até 10 e falha acima:
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
