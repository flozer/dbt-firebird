{#
    Criação de tabelas/views e drops no dialeto Firebird.

    Restrições do dialeto (validadas no Firebird 5):
    - não existe CREATE TABLE AS SELECT: o adaptador descreve a query
      via PREPARE e gera o CREATE TABLE com as colunas; o INSERT é feito
      nas materializations, em transação separada;
    - DROP sem CASCADE e sem IF EXISTS (a existência é controlada pelo
      cache de relações do dbt);
    - não existe rename de tabelas: as materializations do adaptador
      trocam dados por DELETE + INSERT atômico (MVCC).
#}
{% macro firebird__create_table_as(temporary, relation, compiled_code, language='sql') -%}
  {%- if language == 'sql' -%}
    {%- set cols = adapter.get_column_schema_from_query(compiled_code) -%}
    {{ firebird_create_table_ddl_from_cols(relation, cols, compiled_code) }}
  {%- else -%}
    {{ exceptions.raise_compiler_error("python models are not supported by dbt-firebird") }}
  {%- endif -%}
{%- endmacro %}


{# Gera o CREATE TABLE. Com contracts, usa as colunas declaradas no yaml. #}
{% macro firebird_create_table_ddl_from_cols(relation, cols, sql) -%}
  {%- set contract_config = config.get('contract') -%}
  {%- if contract_config is not none and contract_config.enforced -%}
    {{ get_assert_columns_equivalent(sql) }}
    create table {{ relation.render() }} {{ get_table_columns_and_constraints() }}
  {%- else -%}
    create table {{ relation.render() }} (
      {%- for col in cols -%}
        {{ adapter.quote(col.name) }} {{ col.data_type }}{{ ", " if not loop.last }}
      {%- endfor -%}
    )
  {%- endif -%}
{%- endmacro %}


{# INSERT INTO ... SELECT ... com a lista de colunas descritas #}
{% macro firebird_insert_select(target_relation, cols, sql) -%}
  {%- set quoted = [] -%}
  {%- for col in cols -%}
    {%- do quoted.append(adapter.quote(col.name)) -%}
  {%- endfor -%}
  insert into {{ target_relation.render() }} ({{ quoted | join(', ') }})
  select {{ quoted | join(', ') }} from (
    {{ sql }}
  ) dbt_fb_src
{%- endmacro %}


{% macro firebird__create_view_as(relation, sql) -%}
  create or alter view {{ relation.render() }} as
  {{ sql }}
{%- endmacro %}


{% macro firebird__drop_table(relation) -%}
  drop table {{ relation.render() }}
{%- endmacro %}


{% macro firebird__drop_view(relation) -%}
  drop view {{ relation.render() }}
{%- endmacro %}


{% macro firebird__get_rename_table_sql(relation, new_name) %}
  {{ exceptions.raise_compiler_error(
      "Firebird não suporta rename de tabelas. Essa operação não é usada pelas materializations do dbt-firebird.") }}
{% endmacro %}


{% macro firebird__get_rename_view_sql(relation, new_name) %}
  {{ exceptions.raise_compiler_error(
      "Firebird não suporta rename de views. Essa operação não é usada pelas materializations do dbt-firebird.") }}
{% endmacro %}


{% macro firebird__get_replace_table_sql(relation, sql) %}
  {{ exceptions.raise_compiler_error(
      "get_replace_table_sql não é suportado no dbt-firebird; a substituição é feita pela materialization table.") }}
{% endmacro %}


{% macro firebird__get_replace_view_sql(relation, sql) %}
  {{ exceptions.raise_compiler_error(
      "get_replace_view_sql não é suportado no dbt-firebird; a substituição é feita pela materialization view.") }}
{% endmacro %}
