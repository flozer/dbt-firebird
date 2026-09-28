{#
    O Firebird não aceita `select *, expr` — o asterisco precisa ser
    qualificado (alias.*). Os macros default do snapshot usam `select *, ...`
    nos CTEs, por isso são reescritos aqui com o asterisco qualificado.
#}
{% macro build_snapshot_staging_table(strategy, sql, target_relation) %}
    {%- set temp_relation = make_temp_relation(target_relation) -%}
    {%- set stale_staging = load_cached_relation(temp_relation) -%}
    {% if stale_staging is not none %}
      {%- call statement('drop_stale_snapshot_staging') -%}
        drop table {{ stale_staging.render() }}
      {%- endcall -%}
      {% do adapter.commit() %}
    {% endif %}
    {%- set select = snapshot_staging_table(strategy, sql, target_relation) -%}
    {%- set cols = adapter.get_column_schema_from_query(select) -%}
    {# largura da staging nunca menor que a da alvo (describe de UNION pode ser impreciso) #}
    {%- set cols = adapter.pad_columns_to_target(cols, adapter.describe_relation(target_relation)) -%}
    {% call statement('build_snapshot_staging_relation') -%}
        {{ firebird_create_table_ddl_from_cols(temp_relation, cols, select) }}
    {%- endcall %}
    {# DDL precisa commitar antes do DML (snapshot de metadados) #}
    {% do adapter.commit() %}
    {% call statement('build_snapshot_staging_load') -%}
        {{ firebird_insert_select(temp_relation, cols, select) }}
    {%- endcall %}
    {% do adapter.commit() %}
    {% do return(temp_relation) %}
{% endmacro %}


{% macro firebird__build_snapshot_table(strategy, sql) -%}
  {%- set columns = config.get('snapshot_table_column_names') or get_snapshot_table_column_names() -%}
  select
    sbq.*,
    {{ strategy.scd_id }} as {{ columns.dbt_scd_id }},
    {{ strategy.updated_at }} as {{ columns.dbt_updated_at }},
    {{ strategy.updated_at }} as {{ columns.dbt_valid_from }},
    {{ get_dbt_valid_to_current(strategy, columns) }}
    {%- if strategy.hard_deletes == 'new_record' -%}
      , cast('False' as varchar(10)) as {{ columns.dbt_is_deleted }}
    {%- endif -%}
  from (
    {{ sql }}
  ) sbq
{%- endmacro %}


{% macro firebird__snapshot_staging_table(strategy, source_sql, target_relation) -%}
  {%- set columns = config.get('snapshot_table_column_names') or get_snapshot_table_column_names() -%}
  {%- if strategy.hard_deletes == 'new_record' -%}
      {%- set new_scd_id = snapshot_hash_arguments([columns.dbt_scd_id, snapshot_get_time()]) -%}
  {%- endif -%}

  with snapshot_query as (

      {{ source_sql }}

  ),

  snapshotted_data as (

      select sd.*, {{ unique_key_fields(strategy.unique_key) }}
      from {{ target_relation.render() }} sd
      where
          {% if config.get('dbt_valid_to_current') %}
      {%- set source_unique_key = columns.dbt_valid_to | trim %}
      {%- set target_unique_key = config.get('dbt_valid_to_current') | trim %}
              ( {{ equals(source_unique_key, target_unique_key) }} or {{ source_unique_key }} is null )
          {% else %}
              {{ columns.dbt_valid_to }} is null
          {% endif %}

  ),

  insertions_source_data as (

      select isd.*, {{ unique_key_fields(strategy.unique_key) }},
          {{ strategy.updated_at }} as {{ columns.dbt_updated_at }},
          {{ strategy.updated_at }} as {{ columns.dbt_valid_from }},
          {{ get_dbt_valid_to_current(strategy, columns) }},
          {{ strategy.scd_id }} as {{ columns.dbt_scd_id }}
      from snapshot_query isd

  ),

  updates_source_data as (

      select usd.*, {{ unique_key_fields(strategy.unique_key) }},
          {{ strategy.updated_at }} as {{ columns.dbt_updated_at }},
          {{ strategy.updated_at }} as {{ columns.dbt_valid_from }},
          {{ strategy.updated_at }} as {{ columns.dbt_valid_to }}
      from snapshot_query usd

  ),

  {%- if strategy.hard_deletes == 'invalidate' or strategy.hard_deletes == 'new_record' %}

  deletes_source_data as (

      select dsd.*, {{ unique_key_fields(strategy.unique_key) }}
      from snapshot_query dsd

  ),
  {% endif %}

  insertions as (

      select
          cast('insert' as varchar(20)) as dbt_change_type,
          source_data.*
        {%- if strategy.hard_deletes == 'new_record' -%}
          , cast('False' as varchar(10)) as {{ columns.dbt_is_deleted }}
        {%- endif %}
      from insertions_source_data as source_data
      left outer join snapshotted_data
          on {{ unique_key_join_on(strategy.unique_key, "snapshotted_data", "source_data") }}
      where {{ unique_key_is_null(strategy.unique_key, "snapshotted_data") }}
          or ({{ unique_key_is_not_null(strategy.unique_key, "snapshotted_data") }} and (
             {{ strategy.row_changed }} {%- if strategy.hard_deletes == 'new_record' -%} or snapshotted_data.{{ columns.dbt_is_deleted }} = 'True' {% endif %}
          ))
  ),

  updates as (

      select
          cast('update' as varchar(20)) as dbt_change_type,
          source_data.*,
          snapshotted_data.{{ columns.dbt_scd_id }}
        {%- if strategy.hard_deletes == 'new_record' -%}
          , snapshotted_data.{{ columns.dbt_is_deleted }}
        {%- endif %}
      from updates_source_data as source_data
      join snapshotted_data
          on {{ unique_key_join_on(strategy.unique_key, "snapshotted_data", "source_data") }}
      where (
          {{ strategy.row_changed }} {%- if strategy.hard_deletes == 'new_record' -%} or snapshotted_data.{{ columns.dbt_is_deleted }} = 'True' {% endif %}
      )
  )

  {%- if strategy.hard_deletes == 'invalidate' or strategy.hard_deletes == 'new_record' %}
  ,
  deletes as (

      select
          cast('delete' as varchar(20)) as dbt_change_type,
          source_data.*,
          {{ snapshot_get_time() }} as {{ columns.dbt_valid_from }},
          {{ snapshot_get_time() }} as {{ columns.dbt_updated_at }},
          {{ snapshot_get_time() }} as {{ columns.dbt_valid_to }},
          snapshotted_data.{{ columns.dbt_scd_id }}
        {%- if strategy.hard_deletes == 'new_record' -%}
          , snapshotted_data.{{ columns.dbt_is_deleted }}
        {%- endif %}
      from snapshotted_data
      left join deletes_source_data as source_data
          on {{ unique_key_join_on(strategy.unique_key, "snapshotted_data", "source_data") }}
      where {{ unique_key_is_null(strategy.unique_key, "source_data") }}
        {%- if strategy.hard_deletes == 'new_record' %}
          and not (
              snapshotted_data.{{ columns.dbt_is_deleted }} = 'True'
              and
              {% if config.get('dbt_valid_to_current') -%}
                  snapshotted_data.{{ columns.dbt_valid_to }} = {{ config.get('dbt_valid_to_current') }}
              {%- else -%}
                  snapshotted_data.{{ columns.dbt_valid_to }} is null
              {%- endif %}
          )
        {%- endif %}
  )
  {%- endif %}

  {%- if strategy.hard_deletes == 'new_record' %}
      {%- set snapshotted_cols = get_list_of_column_names(get_columns_in_relation(target_relation)) -%}
      {%- set source_col_names = get_columns_in_query(source_sql) -%}
  ,
  deletion_records as (

      select
          cast('insert' as varchar(20)) as dbt_change_type,
          {%- for col_name in source_col_names -%}
          {%- if col_name in snapshotted_cols -%}
          snapshotted_data.{{ adapter.quote(col_name) }},
          {%- else -%}
          source_data.{{ adapter.quote(col_name) }},
          {%- endif -%}
          {% endfor -%}
          {%- if strategy.unique_key | is_list -%}
              {%- for key in strategy.unique_key -%}
          snapshotted_data.{{ key }} as dbt_unique_key_{{ loop.index }},
              {% endfor -%}
          {%- else -%}
          snapshotted_data.dbt_unique_key as dbt_unique_key,
          {% endif -%}
          {{ snapshot_get_time() }} as {{ columns.dbt_valid_from }},
          {{ snapshot_get_time() }} as {{ columns.dbt_updated_at }},
          snapshotted_data.{{ columns.dbt_valid_to }} as {{ columns.dbt_valid_to }},
          {{ new_scd_id }} as {{ columns.dbt_scd_id }},
          cast('True' as varchar(10)) as {{ columns.dbt_is_deleted }}
      from snapshotted_data
      left join deletes_source_data as source_data
          on {{ unique_key_join_on(strategy.unique_key, "snapshotted_data", "source_data") }}
      where {{ unique_key_is_null(strategy.unique_key, "source_data") }}
      and not (
          snapshotted_data.{{ columns.dbt_is_deleted }} = 'True'
          and
          {% if config.get('dbt_valid_to_current') -%}
              snapshotted_data.{{ columns.dbt_valid_to }} = {{ config.get('dbt_valid_to_current') }}
          {%- else -%}
              snapshotted_data.{{ columns.dbt_valid_to }} is null
          {%- endif %}
          )
  )
  {%- endif %}

  select * from insertions
  union all
  select * from updates
  {%- if strategy.hard_deletes == 'invalidate' or strategy.hard_deletes == 'new_record' %}
  union all
  select * from deletes
  {%- endif %}
  {%- if strategy.hard_deletes == 'new_record' %}
  union all
  select * from deletion_records
  {%- endif %}
{%- endmacro %}
