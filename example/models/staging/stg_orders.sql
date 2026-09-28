select
    id as order_id,
    customer_id,
    status,
    order_date,
    total
from {{ ref('raw_orders') }}
where status <> 'cancelled'
