with orders as (
    select * from {{ ref('stg_orders') }}
),

customer_orders as (
    select
        customer_id,
        count(*) as total_orders,
        sum(total) as lifetime_value
    from orders
    group by customer_id
),

final as (
    select
        c.customer_id,
        c.customer_name,
        coalesce(o.total_orders, 0) as total_orders,
        coalesce(o.lifetime_value, 0) as lifetime_value
    from {{ ref('stg_customers') }} c
    left join customer_orders o
        on c.customer_id = o.customer_id
)

select * from final
