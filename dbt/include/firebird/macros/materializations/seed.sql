{#
    Materialização seed para o Firebird.

    - tabela inexistente: CREATE TABLE; commit; INSERTs; commit
    - tabela existente com as mesmas colunas: DELETE + INSERTs na mesma
      transação (atômico; preserva views que dependem da tabela) — o
      --full-refresh também passa por aqui
    - tabela existente com colunas diferentes: drop + create + insert
      (falha se houver views dependentes — no Firebird, DROP TABLE é
      bloqueado por dependências; derrube as views antes)
    - INSERT multi-row (VALUES (..),(..)) não existe no Firebird: o batch
      é 1 (firebird__get_batch_size) e os bindings são qmark
#}
{% materialization seed, adapter='firebird' -%}

  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set old_relation = adapter.get_relation(database=database, schema=schema, identifier=identifier) -%}
  {%- set exists_as_table = (old_relation is not none and old_relation.is_table) -%}
  {%- set exists_as_view = (old_relation is not none and old_relation.is_view) -%}
  {%- set grant_config = config.get('grants') -%}
  {%- set agate_table = load_agate_table() -%}
  {%- do store_result('agate_table', response='OK', agate_table=agate_table) -%}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if exists_as_view %}
    {{ exceptions.raise_compiler_error("Cannot seed to '{}', it is a view".format(old_relation.render())) }}
  {% endif %}

  {%- set rows_affected = (agate_table.rows | length) -%}

  {%- set same_columns = false -%}
  {%- if exists_as_table -%}
    {%- set existing_cols = adapter.get_columns_in_relation(old_relation) | map(attribute='name') | map('lower') | list -%}
    {%- set csv_cols = agate_table.column_names | map('lower') | list -%}
    {%- set same_columns = (existing_cols == csv_cols) -%}
  {%- endif -%}

  {% if exists_as_table and same_columns %}
    {# substitui os dados atomicamente: delete + inserts + commit #}
    {% call statement('reset_seed') -%}
      delete from {{ old_relation.render() }}
    {%- endcall %}
    {% if rows_affected > 0 %}
      {{ firebird_load_seed_rows(model, agate_table) }}
    {% endif %}
    {% do adapter.commit() %}
  {% else %}
    {% if exists_as_table %}
      {% call statement('drop_seed') -%}
        drop table {{ old_relation.render() }}
      {%- endcall %}
      {% do adapter.commit() %}
    {% endif %}
    {# create_csv_table executa o create via statement('_') interno #}
    {% set create_table_sql = create_csv_table(model, agate_table) %}
    {% do adapter.commit() %}
    {% if rows_affected > 0 %}
      {{ firebird_load_seed_rows(model, agate_table) }}
      {% do adapter.commit() %}
    {% endif %}
  {% endif %}

  {% set target_relation = this.incorporate(type='table') %}

  {# registro do resultado 'main' esperado pelo runner (sem executar nada) #}
  {% set code = 'INSERT' if (exists_as_table and same_columns) else 'CREATE' %}
  {% call noop_statement('main', code ~ ' ' ~ rows_affected, code, rows_affected) %}
    -- dbt seed --
  {% endcall %}

  {% if not exists_as_table %}
    {% do create_indexes(target_relation) %}
  {% endif %}

  {% set should_revoke = should_revoke(old_relation, full_refresh_mode) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}
  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=True) }}
  {% do adapter.commit() %}
  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}


{# replica default__load_csv_rows, mas sem statement('main'): os inserts são #}
{# adicionados via add_query e commitados pela materialização                 #}
{% macro firebird_load_seed_rows(model, agate_table) %}
  {% set batch_size = get_batch_size() %}
  {% set cols_sql = get_seed_column_quoted_csv(model, agate_table.column_names) %}

  {% for chunk in agate_table.rows | batch(batch_size) %}
      {% set bindings = [] %}
      {% for row in chunk %}
          {% for value in row %}
              {% do bindings.append(adapter.seed_binding(value)) %}
          {% endfor %}
      {% endfor %}

      {% set sql %}
          insert into {{ this.render() }} ({{ cols_sql }}) values
          {% for row in chunk -%}
              ({%- for column in agate_table.column_names -%}
                  {{ get_binding_char() }}
                  {%- if not loop.last%},{%- endif %}
              {%- endfor -%})
              {%- if not loop.last%},{%- endif %}
          {%- endfor %}
      {% endset %}

      {% do adapter.add_query(sql, bindings=bindings, abridge_sql_log=True) %}
  {% endfor %}
{% endmacro %}
