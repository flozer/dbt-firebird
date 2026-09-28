{#
    O Firebird nao tem schemas: todos os objetos vivem em um namespace unico.
    Os macros de schema sao no-ops que sempre reportam o schema do target
    como existente.
#}
{% macro firebird__create_schema(relation) -%}
  {%- call statement('create_schema') -%}
    select 1 from rdb$database
  {%- endcall -%}
{% endmacro %}


{% macro firebird__drop_schema(relation) -%}
  {%- call statement('drop_schema') -%}
    select 1 from rdb$database
  {%- endcall -%}
{% endmacro %}


{% macro firebird__list_schemas(database) -%}
  {%- set sql -%}
    select '{{ target.schema }}' as schema_name from rdb$database
  {%- endset -%}
  {{ return(run_query(sql)) }}
{%- endmacro %}


{% macro firebird__check_schema_exists(information_schema, schema) -%}
  {%- set sql -%}
    select case when '{{ schema }}' = '{{ target.schema }}' then 1 else 0 end as schema_exists
    from rdb$database
  {%- endset -%}
  {{ return(run_query(sql)) }}
{%- endmacro %}
