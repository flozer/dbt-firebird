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
