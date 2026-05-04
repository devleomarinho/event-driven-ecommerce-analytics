-- Substitui o mart_order_funnel.sql atual por:

{{ config(materialized='table') }}

with orders as (
    select * from {{ ref('fct_orders') }}
),

-- Agrupa pelo estado atual de cada pedido
status_counts as (
    select
        current_status,
        count(*) as orders_count,
        sum(order_amount) as revenue_in_status,
        avg(order_amount) as avg_amount
    from orders
    group by 1
),

-- Adiciona ordering do funil
status_ordered as (
    select
        case current_status
            when 'created'   then 1
            when 'paid'      then 2
            when 'shipped'   then 3
            when 'delivered' then 4
            when 'canceled'  then 5
            else 99
        end as funnel_step,
        current_status as status_name,
        orders_count,
        revenue_in_status,
        avg_amount
    from status_counts
),

-- Total de pedidos para calcular percentuais
totals as (
    select sum(orders_count) as total_orders 
    from status_ordered
),

final as (
    select
        s.funnel_step,
        s.status_name,
        s.orders_count,
        s.revenue_in_status,
        round(s.avg_amount, 2) as avg_amount,
        round(s.orders_count * 1.0 / t.total_orders, 4) as pct_of_total,
        current_timestamp() as dbt_computed_at
    from status_ordered s
    cross join totals t
)

select * from final
order by funnel_step