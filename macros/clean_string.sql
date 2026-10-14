{#- Remove espaços nas pontas e converte string vazia em nulo.
    Usada nos dois modelos de staging. -#}
{% macro clean_string(column_name) -%}
    nullif(trim({{ column_name }}), '')
{%- endmacro %}
