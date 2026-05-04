{{ config(materialized='table') }}

{# 
    mart_daily_revenue — agregacao diaria de receita por estado.
    
    Granularidade: 1 linha por (dia, estado).
    Pre-calcula metricas para dashboards executivos.
    
    Joins necessarios:
    - fct_orders -> dim_customers (para state)
    - fct_orders -> dim_date (para atributos temporais)
#}

with orders as (
    select * from {{ ref('fct_orders') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

dates as (
    select * from {{ ref('dim_date') }}
),

-- ---------------------------------------------------------------------
-- Junta fato com dimensoes para enriquecer com atributos
-- ---------------------------------------------------------------------
enriched as (
    select
        d.date_key                  as day_date_key,
        d.full_date                 as day_date,
        d.year_month,
        d.day_name_short,
        d.is_weekend,
        c.state                     as customer_state,
        o.order_id,
        o.customer_sk,
        o.order_amount,
        o.item_count,
        o.is_completed,
        o.is_delivered
    from orders o
    inner join customers c on o.customer_sk = c.customer_sk
    inner join dates     d on o.created_date_key = d.date_key
),

-- ---------------------------------------------------------------------
-- Agrega por dia e estado
-- ---------------------------------------------------------------------
final as (
    select
        -- Granularidade
        day_date_key,
        day_date,
        year_month,
        day_name_short,
        is_weekend,
        customer_state,

        -- Volumes
        count(distinct order_id)              as orders_count,
        count(distinct customer_sk)           as unique_customers,

        -- Receita
        sum(order_amount)                     as gross_revenue,
        avg(order_amount)                     as avg_order_value,
        min(order_amount)                     as min_order_value,
        max(order_amount)                     as max_order_value,

        -- Items
        sum(item_count)                       as total_items_sold,
        avg(item_count)                       as avg_items_per_order,

        -- Pedidos por status (proporcoes)
        sum(case when is_completed then 1 else 0 end)     as completed_orders,
        sum(case when is_delivered then 1 else 0 end)     as delivered_orders,
        
        -- Taxas (rate = 0-1, multiplicar por 100 para percentual)
        sum(case when is_completed then 1 else 0 end) * 1.0 / count(*) as completion_rate,
        sum(case when is_delivered then 1 else 0 end) * 1.0 / count(*) as delivery_rate,

        -- Auditoria
        current_timestamp() as dbt_computed_at

    from enriched
    group by 1, 2, 3, 4, 5, 6
)

select * from final