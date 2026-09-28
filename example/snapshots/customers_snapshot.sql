{% snapshot customers_snapshot %}

{{
    config(
        target_schema=schema,
        unique_key='customer_id',
        strategy='check',
        check_cols=['customer_name'],
        invalidate_hard_deletes=True
    )
}}

select customer_id, customer_name from {{ ref('stg_customers') }}

{% endsnapshot %}
