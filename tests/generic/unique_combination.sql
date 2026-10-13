{#- Equivalente a dbt_utils.unique_combination_of_columns, sem depender de
    pacote (D6). Retorna uma linha por combinação repetida. -#}
{% test unique_combination(model, combination_of_columns) %}
select
    {{ combination_of_columns | join(', ') }},
    count(*) as n_records
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1
{% endtest %}
