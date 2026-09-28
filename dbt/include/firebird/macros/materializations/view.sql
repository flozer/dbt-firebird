{#
    Materialização view para o Firebird: CREATE OR ALTER VIEW é atômico.
    Se o nome está ocupado por uma tabela, ela é derrubada antes.
#}
{% materialization view, adapter='firebird' -%}

  {%- set existing_relation = load_cached_relation(this) -%}
  {%- set target_relation = this.incorporate(type='view') -%}
  {%- set grant_config = config.get('grants') -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if existing_relation is not none and existing_relation.type == 'table' %}
    {% call statement('drop_existing_table') -%}
      drop table {{ existing_relation.render() }}
    {%- endcall %}
    {% do adapter.commit() %}
  {% endif %}

  {% call statement('main') -%}
    {%- set contract_config = config.get('contract') -%}
    {%- if contract_config is not none and contract_config.enforced -%}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif -%}
    {{ firebird__create_view_as(target_relation, sql) }}
  {%- endcall %}
  {% do adapter.commit() %}

  {% set should_revoke = should_revoke(existing_relation, full_refresh_mode=True) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}
  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}
  {% do adapter.commit() %}
  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
