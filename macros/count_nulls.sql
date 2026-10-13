{#- Conta quantas das colunas recebidas são nulas na linha. Usada para
    escolher o registro mais completo ao deduplicar clientes (D10). -#}
{% macro count_nulls(columns) -%}
    ({% for column in columns -%}
        case when {{ column }} is null then 1 else 0 end
        {%- if not loop.last %} + {% endif %}
    {%- endfor %})
{%- endmacro %}
