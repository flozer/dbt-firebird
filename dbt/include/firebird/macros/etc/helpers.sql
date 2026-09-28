{#
    Helpers compartilhados pelas materializations do dbt-firebird.

    Regra do dialeto (Firebird 3+): statements compilam contra o snapshot de
    metadados da transação — DDL executado na mesma transação não é visível
    para o DML seguinte. Por isso todo DDL é commitado antes do DML que o usa.
#}

{#
    Constrói a tabela alvo (nova) e carrega os dados. Como CREATE TABLE não é
    visível para o INSERT na mesma transação, o carregamento acontece em duas
    transações: create + commit, depois insert + commit.
#}
{% macro firebird_create_and_load(target_relation, cols, sql) %}
  {% call statement('create_table') -%}
    {{ firebird_create_table_ddl_from_cols(target_relation, cols, sql) }}
  {%- endcall %}
  {% do adapter.commit() %}

  {% call statement('main') -%}
    {{ firebird_insert_select(target_relation, cols, sql) }}
  {%- endcall %}
  {% do adapter.commit() %}
{% endmacro %}


{#
    Substitui uma tabela existente por uma nova versão da query:
    1. staging `__dbt_tmp` criada e carregada em transações separadas;
    2. se as colunas são compatíveis: DELETE + INSERT + DROP na mesma
       transação — atômico para leitores (MVCC);
    3. se incompatíveis: drop + recreate da alvo e insert a partir da staging
       (janela curta com a tabela vazia; a staging já contém os dados novos).
#}
{% macro firebird_swap_existing_table(existing_relation, target_relation, cols, sql) %}
  {%- set staging = make_temp_relation(target_relation) -%}
  {%- set preexisting_tmp = load_cached_relation(staging) -%}
  {% if preexisting_tmp is not none %}
    {% call statement('drop_stale_staging') -%}
      drop table {{ staging.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
  {% endif %}

  {% call statement('create_staging') -%}
    {{ firebird_create_table_ddl_from_cols(staging, cols, sql) }}
  {%- endcall %}
  {% do adapter.commit() %}

  {% call statement('load_staging') -%}
    {{ firebird_insert_select(staging, cols, sql) }}
  {%- endcall %}
  {% do adapter.commit() %}

  {%- set staging_cols = adapter.describe_relation(staging) -%}
  {% set compatible = firebird_columns_compatible(adapter.describe_relation(existing_relation), staging_cols) %}

  {% if compatible %}
    {% call statement('swap_delete') -%}
      delete from {{ existing_relation.render() }}
    {%- endcall %}
    {% call statement('main') -%}
      {{ firebird_insert_from_staging(existing_relation, staging_cols, staging) }}
    {%- endcall %}
    {% call statement('drop_staging') -%}
      drop table {{ staging.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
  {% else %}
    {% call statement('drop_target') -%}
      drop {{ 'view' if existing_relation.type == 'view' else 'table' }} {{ existing_relation.render() }}
    {%- endcall %}
    {% call statement('recreate_target') -%}
      {{ firebird_create_table_ddl_from_cols(target_relation, cols, sql) }}
    {%- endcall %}
    {% do adapter.commit() %}
    {% call statement('main') -%}
      {{ firebird_insert_from_staging(target_relation, staging_cols, staging) }}
    {%- endcall %}
    {% call statement('drop_staging') -%}
      drop table {{ staging.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
  {% endif %}
{% endmacro %}


{# INSERT INTO alvo SELECT ... FROM staging (colunas já descritas da staging) #}
{% macro firebird_insert_from_staging(target_relation, staging_cols, staging_relation) -%}
  {%- set quoted = [] -%}
  {%- for col in staging_cols -%}
    {%- do quoted.append(adapter.quote(col.name)) -%}
  {%- endfor -%}
  insert into {{ target_relation.render() }} ({{ quoted | join(', ') }})
  select {{ quoted | join(', ') }} from {{ staging_relation.render() }}
{%- endmacro %}


{#
    Compara duas listas de colunas: nomes iguais e mesma família de tipo
    (tamanhos/precision podem divergir — o Firebird falha o INSERT se os
    dados não couberem, e a transação atômica desfaz o swap).
#}
{% macro firebird_columns_compatible(cols_a, cols_b) %}
  {%- if cols_a | length != cols_b | length -%}
    {{ return(false) }}
  {%- endif -%}
  {%- for a in cols_a -%}
    {%- set b = cols_b[loop.index0] -%}
    {%- if a.name | lower != b.name | lower -%}
      {{ return(false) }}
    {%- endif -%}
    {%- if firebird_type_family(a.data_type) != firebird_type_family(b.data_type) -%}
      {{ return(false) }}
    {%- endif -%}
  {%- endfor -%}
  {{ return(true) }}
{% endmacro %}


{# VARCHAR(50) -> VARCHAR; DECIMAL(10,2) -> DECIMAL; etc. #}
{% macro firebird_type_family(dtype) %}
  {{ return((dtype | string).split('(')[0] | trim | upper) }}
{% endmacro %}
