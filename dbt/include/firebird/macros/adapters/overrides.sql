{# bindings: firebird-driver usa paramstyle qmark #}
{% macro firebird__get_binding_char() %}
  {{ return('?') }}
{% endmacro %}

{# INSERT multi-row (VALUES (..),(..)) não existe no Firebird #}
{% macro firebird__get_batch_size() %}
  {{ return(1) }}
{% endmacro %}

{#
    Hash dos snapshots: o Firebird não tem md5() nativo; HASH() (BIGINT,
    FNV1a-64) atende ao propósito do dbt_scd_id.
#}
{% macro firebird__snapshot_hash_arguments(args) -%}
  hash(
    {%- for arg in args -%}
      coalesce(cast({{ arg }} as varchar(8191)), '')
      {%- if not loop.last -%} || '|' || {%- endif -%}
    {%- endfor -%}
  )
{%- endmacro %}

{#
    O macro global monta `select CURRENT_TIMESTAMP as dbt_snapshot_time`
    (sem FROM — inválido no Firebird). O tipo do CURRENT_TIMESTAMP é fixo,
    então retorna direto.
#}
{% macro get_snapshot_get_time_data_type() %}
  {{ return('TIMESTAMP') }}
{% endmacro %}


{#
    O default usa `explain`, que o Firebird não suporta da mesma forma.
    Valida a query preparando-a sem executar linhas.
#}
{% macro firebird__validate_sql(sql) -%}
  {%- call statement('validate_sql', fetch_result=True, auto_begin=False) -%}
    select first 0 * from (
      {{ sql }}
    ) dbt_sbq
  {%- endcall -%}
  {{ return(load_result('validate_sql')) }}
{%- endmacro %}


{#
    Converte string para literal de timestamp (usada por snapshots quando o
    `updated_at` configurado é um literal).
#}
{% macro firebird__snapshot_string_as_time(timestamp) %}
  {%- set escaped = timestamp | string | replace("'", "''") -%}
  {{ return("TIMESTAMP '" ~ escaped ~ "'") }}
{% endmacro %}
