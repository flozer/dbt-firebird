{#
    A ordem das colunas é o contrato do SQLAdapter.list_relations_without_caching:
    (database, name, schema, type) — o Python constrói as Relations a partir delas.
#}
{% macro firebird__list_relations_without_caching(schema_relation) %}
  {%- set sql -%}
    select
      '{{ schema_relation.database }}' as database_name,
      trim(r.rdb$relation_name) as relation_name,
      '{{ schema_relation.schema }}' as schema_name,
      trim(case when coalesce(r.rdb$relation_type, 0) = 1 then 'view' else 'table' end) as relation_type
    from rdb$relations r
    where coalesce(r.rdb$system_flag, 0) = 0
      and coalesce(r.rdb$relation_type, 0) in (0, 1, 2)
      and r.rdb$relation_name not starting 'RDB$'
  {%- endset -%}
  {{ return(run_query(sql)) }}
{% endmacro %}


{# catalogo usado pelo `dbt docs generate` #}
{% macro firebird__get_catalog(information_schema, schemas) -%}
  {%- set sql -%}
    select
      '{{ target.database }}' as "table_database",
      '{{ target.schema }}' as "table_schema",
      trim(r.rdb$relation_name) as "table_name",
      case when coalesce(r.rdb$relation_type, 0) = 1 then 'VIEW' else 'BASE TABLE' end as "table_type",
      trim(f.rdb$field_name) as "column_name",
      f.rdb$field_position as "column_index",
      {{ firebird_catalog_column_type() }} as "column_type",
      null as "table_comment",
      null as "table_owner",
      null as "column_comment"
    from rdb$relations r
    join rdb$relation_fields f
      on f.rdb$relation_name = r.rdb$relation_name
    join rdb$fields fld
      on fld.rdb$field_name = f.rdb$field_source
    left join rdb$character_sets cs
      on cs.rdb$character_set_id = fld.rdb$character_set_id
    where coalesce(r.rdb$system_flag, 0) = 0
      and coalesce(r.rdb$relation_type, 0) in (0, 1, 2)
    order by 3, 5
  {%- endset -%}
  {{ return(run_query(sql)) }}
{%- endmacro %}


{# expressao SQL que descreve o tipo de uma coluna a partir de RDB$FIELDS #}
{# codigos de armazenamento RDB$FIELD_TYPE (validados no Firebird 5.0)   #}
{% macro firebird_catalog_column_type() -%}
  case
    when fld.rdb$field_type = 14 then 'CHAR(' || (fld.rdb$field_length / coalesce(cs.rdb$bytes_per_character, 1)) || ')'
    when fld.rdb$field_type = 37 then 'VARCHAR(' || (fld.rdb$field_length / coalesce(cs.rdb$bytes_per_character, 1)) || ')'
    when fld.rdb$field_type = 7 then case when fld.rdb$field_sub_type is not null and fld.rdb$field_sub_type <> 0 then 'DECIMAL(' || coalesce(fld.rdb$field_precision, 18) || ',' || abs(fld.rdb$field_scale) || ')' else 'SMALLINT' end
    when fld.rdb$field_type = 8 then case when fld.rdb$field_sub_type is not null and fld.rdb$field_sub_type <> 0 then 'DECIMAL(' || coalesce(fld.rdb$field_precision, 18) || ',' || abs(fld.rdb$field_scale) || ')' else 'INTEGER' end
    when fld.rdb$field_type = 16 then case when fld.rdb$field_sub_type in (1, 2) then 'DECIMAL(' || coalesce(fld.rdb$field_precision, 18) || ',' || abs(fld.rdb$field_scale) || ')' else 'BIGINT' end
    when fld.rdb$field_type = 10 then 'FLOAT'
    when fld.rdb$field_type = 11 then 'DOUBLE PRECISION'
    when fld.rdb$field_type = 27 then 'DOUBLE PRECISION'
    when fld.rdb$field_type = 35 then 'TIMESTAMP'
    when fld.rdb$field_type = 28 then 'TIMESTAMP WITH TIME ZONE'
    when fld.rdb$field_type = 12 then 'DATE'
    when fld.rdb$field_type = 13 then 'TIME'
    when fld.rdb$field_type = 29 then 'TIME WITH TIME ZONE'
    when fld.rdb$field_type = 23 then 'BOOLEAN'
    when fld.rdb$field_type = 261 then case when fld.rdb$field_sub_type = 1 then 'BLOB SUB_TYPE TEXT' else 'BLOB SUB_TYPE BINARY' end
    when fld.rdb$field_type = 24 then 'DECFLOAT(16)'
    when fld.rdb$field_type = 25 then 'DECFLOAT(34)'
    when fld.rdb$field_type = 26 then 'DECFLOAT(38)'
    else 'VARCHAR(8191)'
  end
{%- endmacro %}
