{{
    config(
        materialized='incremental',
        unique_key='order_id'
    )
}}

select
    o.order_id,
    o.customer_id,
    c.customer_name,
    o.status,
    o.total
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c
    on o.customer_id = c.customer_id

{% if is_incremental() %}
where o.order_id > (select coalesce(max(order_id), 0) from {{ this }})
{% endif %}
