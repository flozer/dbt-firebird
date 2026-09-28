{#
    Materialização table para o Firebird.

    - alvo inexistente: CREATE TABLE; commit; INSERT; commit
      (DDL não é visível para o DML na mesma transação — snapshot de metadados)
    - alvo existente como tabela: staging + swap atômico (DELETE + INSERT na
      mesma transação) quando as colunas são compatíveis; caso contrário,
      drop + recreate + insert
    - alvo existente como view: drop da view e criação como tabela
#}
{% materialization table, adapter='firebird' -%}

  {%- set existing_relation = load_cached_relation(this) -%}
  {%- set target_relation = this.incorporate(type='table') -%}
  {%- set grant_config = config.get('grants') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {%- set cols = adapter.get_column_schema_from_query(sql) -%}

  {% if existing_relation is none %}
    {{ firebird_create_and_load(target_relation, cols, sql) }}
  {% elif existing_relation.type == 'table' %}
    {{ firebird_swap_existing_table(existing_relation, target_relation, cols, sql) }}
  {% else %}
    {% call statement('drop_existing_view') -%}
      drop view {{ existing_relation.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
    {{ firebird_create_and_load(target_relation, cols, sql) }}
  {% endif %}

  {% if existing_relation is none or existing_relation.type != 'table' %}
    {% do create_indexes(target_relation) %}
  {% endif %}

  {% set should_revoke = should_revoke(existing_relation, full_refresh_mode=True) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}
  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}
  {% do adapter.commit() %}
  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
