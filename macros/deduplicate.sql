{#- Mantém uma linha por partição, a primeira segundo `order_by`.
    `order_by` deve ser determinístico (incluir um desempate) para que o
    resultado não mude entre execuções. Usada nos dois modelos de staging. -#}
{% macro deduplicate(relation, partition_by, order_by) -%}
    select *
    from (
        select
            *,
            row_number() over (
                partition by {{ partition_by }}
                order by {{ order_by }}
            ) as _dedup_row_number
        from {{ relation }}
    ) as _dedup
    where _dedup_row_number = 1
{%- endmacro %}
