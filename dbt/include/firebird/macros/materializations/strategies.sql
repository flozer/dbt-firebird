{# Strategies incrementais do dbt-firebird #}

{#
    append: o default gera `insert into t (cols) (select ...)` — fonte entre
    parênteses, que o Firebird não aceita. Gera a forma plana.
#}
{% macro firebird__get_incremental_append_sql(arg_dict) %}
  {%- set quoted = [] -%}
  {%- for col in arg_dict["dest_columns"] -%}
    {%- do quoted.append(adapter.quote(col.name)) -%}
  {%- endfor -%}
  insert into {{ arg_dict["target_relation"].render() }} ({{ quoted | join(', ') }})
  select {{ quoted | join(', ') }} from {{ arg_dict["temp_relation"].render() }}
{% endmacro %}


{#
    delete+insert: duas instruções na mesma transação, encapsuladas num
    EXECUTE BLOCK (o dbt executa o retorno como um único statement).
#}
{% macro firebird__get_incremental_delete_insert_sql(arg_dict) %}
  {%- set target = arg_dict["target_relation"] -%}
  {%- set source = arg_dict["temp_relation"] -%}
  {%- set unique_key = arg_dict["unique_key"] -%}
  {%- set dest_columns = arg_dict["dest_columns"] -%}
  {%- set incremental_predicates = arg_dict["incremental_predicates"] -%}

  {%- if not unique_key -%}
    {{ exceptions.raise_compiler_error(
        "a strategy delete+insert exige a config unique_key") }}
  {%- endif -%}

  {%- if unique_key is string -%}
    {%- set unique_key = [unique_key] -%}
  {%- endif -%}

  {%- set quoted = [] -%}
  {%- for col in dest_columns -%}
    {%- do quoted.append(adapter.quote(col.name)) -%}
  {%- endfor -%}

  execute block as begin
    delete from {{ target.render() }} DBT_INTERNAL_DEST
    where exists (
      select 1 from {{ source.render() }} DBT_INTERNAL_SOURCE
      where
        {%- for key in unique_key %}
        DBT_INTERNAL_DEST.{{ key | trim }} = DBT_INTERNAL_SOURCE.{{ key | trim }}
        {%- if not loop.last %} and {% endif %}
        {%- endfor %}
        {%- if incremental_predicates %}
          {%- for predicate in incremental_predicates %}
        and ({{ predicate }})
          {%- endfor %}
        {%- endif %}
    );

    insert into {{ target.render() }} ({{ quoted | join(', ') }})
    select {{ quoted | join(', ') }} from {{ source.render() }};
  end
{% endmacro %}


{#
    merge: MERGE nativo do Firebird (sintaxe validada: aliases com AS e
    referências qualificadas nos sets/inserts).
#}
{% macro firebird__get_incremental_merge_sql(arg_dict) %}
  {%- set target = arg_dict["target_relation"] -%}
  {%- set source = arg_dict["temp_relation"] -%}
  {%- set unique_key = arg_dict["unique_key"] -%}
  {%- set dest_columns = arg_dict["dest_columns"] -%}
  {%- set incremental_predicates = arg_dict["incremental_predicates"] -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) -%}
  {%- set merge_update_columns = config.get('merge_update_columns') -%}
  {%- set merge_exclude_columns = config.get('merge_exclude_columns') -%}
  {%- set update_columns = get_merge_update_columns(merge_update_columns, merge_exclude_columns, dest_columns) -%}

  {{ sql_header if sql_header is not none }}

  merge into {{ target.render() }} as DBT_INTERNAL_DEST
  using {{ source.render() }} as DBT_INTERNAL_SOURCE
  on (
    {%- if unique_key -%}
      {%- if unique_key is string -%}{%- set unique_key = [unique_key] -%}{%- endif -%}
      {%- for key in unique_key %}
      DBT_INTERNAL_DEST.{{ key | trim }} = DBT_INTERNAL_SOURCE.{{ key | trim }}
        {%- if not loop.last %} and {% endif %}
      {%- endfor %}
    {%- else -%}
      1 = 0
    {%- endif -%}
    {%- if incremental_predicates %}
      {%- for predicate in incremental_predicates %}
      and ({{ predicate }})
      {%- endfor %}
    {%- endif %}
  )

  when matched then update set
    {%- for column_name in update_columns %}
      {{ column_name }} = DBT_INTERNAL_SOURCE.{{ column_name }}
      {%- if not loop.last %},{%- endif %}
    {%- endfor %}

  when not matched then insert
    ({{ dest_cols_csv }})
    values ({{ dest_cols_csv }})
{% endmacro %}
