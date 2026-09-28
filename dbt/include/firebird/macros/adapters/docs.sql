{#
    persist_docs: o Firebird suporta COMMENT ON TABLE/COLUMN.

    Contratos do persist_docs default:
    - alter_relation_comment: RETORNA o SQL — o default o executa via
      run_query (o commit acontece no fluxo final da materialização);
    - alter_column_comment: avaliado imediatamente; aqui executamos N
      COMMENTs num único EXECUTE BLOCK (cada coluna é um statement próprio
      no Firebird) e retornamos vazio para o default pular o run_query.

    Aspas simples nas descrições são escapadas ('' padrão SQL); ao embutir
    o statement interno no `execute statement '...'`, todas as aspas são
    dobradas de novo.

    O nome real da coluna no catálogo é resolvido case-insensitivamente: as
    colunas podem ter sido criadas com case diferente das chaves do YAML.
#}
{% macro firebird__alter_relation_comment(relation, relation_comment) -%}
  {%- set escaped = relation_comment | replace("'", "''") -%}
  comment on table {{ relation.render() }} is '{{ escaped }}'
{%- endmacro %}


{% macro firebird__alter_column_comment(relation, column_dict) -%}
  {%- set real_names = {} -%}
  {%- for col in adapter.get_columns_in_relation(relation) -%}
    {%- do real_names.update({col.name | lower: col.name}) -%}
  {%- endfor -%}
  {%- set q = "'" -%}

  {%- set block_sql -%}
execute block as begin
{% for column_name, column in column_dict.items() %}
{% set real_name = real_names.get(column_name | lower, column_name) %}
{% set escaped = (column['description'] or '') | replace("'", "''") %}
{% set comment_sql = 'comment on column ' ~ relation.render() ~ '.' ~ adapter.quote(real_name) ~ ' is ' ~ q ~ escaped ~ q %}
    execute statement '{{ comment_sql | replace("'", "''") }}';
{% endfor %}
end
  {%- endset -%}

  {%- call statement('alter_column_comment', auto_begin=False) -%}
    {{ block_sql }}
  {%- endcall -%}
  {% do adapter.commit() %}
  {{ return('') }}
{%- endmacro %}
