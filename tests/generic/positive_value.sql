{#- Falha para cada linha cujo valor não é estritamente positivo.
    Faz cast para double porque os seeds são carregados como texto (D7);
    valores não numéricos também falham. -#}
{% test positive_value(model, column_name) %}
select *
from {{ model }}
where {{ column_name }} is not null
  and coalesce({{ dbt.safe_cast(column_name, dbt.type_float()) }} <= 0, true)
{% endtest %}
