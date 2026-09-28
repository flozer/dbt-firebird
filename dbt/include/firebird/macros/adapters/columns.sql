{% macro firebird__get_columns_in_relation(relation) -%}
  {{ return(adapter.describe_relation(relation)) }}
{%- endmacro %}


{#
    O default usa `limit 0`, que nao existe no Firebird.
#}
{% macro firebird__get_empty_subquery_sql(select_sql, select_sql_header=none) %}
    {%- if select_sql_header is not none -%}
    {{ select_sql_header }}
    {%- endif -%}
    select first 0 * from (
        {{ select_sql }}
    ) dbt_sbq
{% endmacro %}


{% macro firebird__truncate_relation(relation) -%}
  {%- call statement('truncate_relation') -%}
    delete from {{ relation.render() }}
  {%- endcall -%}
{%- endmacro %}


{% macro firebird__alter_column_type(relation, column_name, new_column_type) -%}
  {%- call statement('alter_column_type') -%}
    alter table {{ relation.render() }} alter column {{ adapter.quote(column_name) }} type {{ new_column_type }}
  {%- endcall -%}
  {# DDL precisa estar commitado antes do DML seguinte (snapshot de metadados) #}
  {% do adapter.commit() %}
{%- endmacro %}


{% macro firebird__alter_relation_add_remove_columns(relation, add_columns, remove_columns) %}
  {% if add_columns is none %}{% set add_columns = [] %}{% endif %}
  {% if remove_columns is none %}{% set remove_columns = [] %}{% endif %}

  {% for column in add_columns %}
    {%- call statement('alter_relation_add_column') -%}
      alter table {{ relation.render() }} add {{ column.quoted }} {{ column.expanded_data_type }}
    {%- endcall -%}
    {% do adapter.commit() %}
  {% endfor %}

  {% for column in remove_columns %}
    {%- call statement('alter_relation_drop_column') -%}
      alter table {{ relation.render() }} drop {{ column.quoted }}
    {%- endcall -%}
    {% do adapter.commit() %}
  {% endfor %}
{% endmacro %}


{# usado pelo fluxo de snapshot (hard_deletes='new_record') #}
{% macro firebird__create_columns(relation, columns) %}
  {% for column in columns %}
    {%- call statement('create_column') -%}
      alter table {{ relation.render() }} add {{ adapter.quote(column.name) }} {{ column.expanded_data_type }}
    {%- endcall -%}
    {% do adapter.commit() %}
  {% endfor %}
{% endmacro %}
