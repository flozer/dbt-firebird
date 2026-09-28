{#
    Materialização incremental para o Firebird.

    - primeira execução: CREATE TABLE; commit; INSERT; commit
    - full refresh: mesmo fluxo da materialização table (swap via staging)
    - incremental: staging __dbt_tmp criada/carregada em transações próprias,
      depois a strategy (append | delete+insert | merge) roda contra a alvo
      já commitada, e a staging é derrubada na mesma transação
#}
{% materialization incremental, adapter='firebird' -%}

  {%- set existing_relation = load_cached_relation(this) -%}
  {%- set target_relation = this.incorporate(type='table') -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set unique_key = config.get('unique_key') -%}
  {%- set on_schema_change = incremental_validate_on_schema_change(config.get('on_schema_change'), default='ignore') -%}
  {%- set incremental_predicates = config.get('predicates', none) or config.get('incremental_predicates', none) -%}
  {%- set grant_config = config.get('grants') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if existing_relation is none %}
    {%- set cols = adapter.get_column_schema_from_query(sql) -%}
    {{ firebird_create_and_load(target_relation, cols, sql) }}
    {% do create_indexes(target_relation) %}

  {% elif existing_relation.type != 'table' %}
    {# alvo é uma view: derruba e constrói a tabela do zero #}
    {% call statement('drop_existing_view') -%}
      drop view {{ existing_relation.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
    {%- set cols = adapter.get_column_schema_from_query(sql) -%}
    {{ firebird_create_and_load(target_relation, cols, sql) }}
    {% do create_indexes(target_relation) %}

  {% elif full_refresh_mode %}
    {%- set cols = adapter.get_column_schema_from_query(sql) -%}
    {{ firebird_swap_existing_table(existing_relation, target_relation, cols, sql) }}
    {% do create_indexes(target_relation) %}

  {% else %}
    {%- set temp_relation = make_temp_relation(target_relation) -%}
    {%- set preexisting_temp = load_cached_relation(temp_relation) -%}
    {% if preexisting_temp is not none %}
      {% call statement('drop_stale_temp') -%}
        drop table {{ temp_relation.render() }}
      {%- endcall %}
      {% do adapter.commit() %}
    {% endif %}

    {%- set cols = adapter.get_column_schema_from_query(sql) -%}
    {% call statement('create_temp') -%}
      {{ firebird_create_table_ddl_from_cols(temp_relation, cols, sql) }}
    {%- endcall %}
    {% do adapter.commit() %}

    {% call statement('load_temp') -%}
      {{ firebird_insert_select(temp_relation, cols, sql) }}
    {%- endcall %}
    {% do adapter.commit() %}

    {#- processa mudanças de schema (fail/ignore/append/sync_all) -#}
    {% set dest_columns = process_schema_changes(on_schema_change, temp_relation, existing_relation) %}
    {% if not dest_columns %}
      {% set dest_columns = adapter.get_columns_in_relation(existing_relation) %}
    {% endif %}

    {%- set incremental_strategy = config.get('incremental_strategy') or 'default' -%}
    {%- set strategy_sql_macro_func = adapter.get_incremental_strategy_macro(context, incremental_strategy) -%}
    {%- set strategy_arg_dict = ({
          'target_relation': target_relation,
          'temp_relation': temp_relation,
          'unique_key': unique_key,
          'dest_columns': dest_columns,
          'incremental_predicates': incremental_predicates
        }) -%}

    {% call statement('main') -%}
      {{ strategy_sql_macro_func(strategy_arg_dict) }}
    {%- endcall %}

    {% call statement('drop_temp') -%}
      drop table {{ temp_relation.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
  {% endif %}

  {% set should_revoke = should_revoke(existing_relation, full_refresh_mode) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}
  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}
  {% do adapter.commit() %}
  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
