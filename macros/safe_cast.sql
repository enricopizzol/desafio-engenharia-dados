{#- O dbt.safe_cast padrão do dbt-duckdb compila para um cast comum, que derruba
    o dbt run com um valor como 'abc'. Este override (o dbt procura primeiro no
    projeto) usa try_cast, que devolve nulo, para o staging filtrar o registro.
    No Postgres não existe try_cast, e lá o comportamento continua o padrão. -#}
{% macro duckdb__safe_cast(field, type) -%}
    try_cast({{ field }} as {{ type }})
{%- endmacro %}
