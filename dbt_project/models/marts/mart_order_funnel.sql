{{ config(materialized='table') }}

{# 
    mart_order_funnel — analise de conversao entre status de pedido.
    
    Granularidade: 1 linha por status.
    Calcula:
    - Quantos pedidos atingiram cada status (orders_reached)
    - Conversao em relacao ao topo (created)
    - Tempo medio para chegar a cada status
    
    Importante: pedidos podem "saltar" status no nosso gerador
    (ver fct_orders). Por exemplo, um pedido pode ir direto de
    "created" para "delivered" sem evento intermediario de "paid".
    Por isso usamos fct_orders.is_delivered (denormalizado) em vez
    de contar transicoes em fct_order_lifecycle.
#}

with orders as (
    select * from {{ ref('fct_orders') }}
),

-- ---------------------------------------------------------------------
-- Total de pedidos (denominador para taxas de conversao)
-- ---------------------------------------------------------------------
totals as (
    select
        count(*) as total_orders,
        sum(order_amount) as total_revenue
    from orders
),

-- ---------------------------------------------------------------------
-- Calcula metricas por status
-- ---------------------------------------------------------------------
status_metrics as (
    -- "Created" — todo pedido passa por aqui
    select
        1                                      as funnel_step,
        'created'                              as status_name,
        count(*)                               as orders_reached,
        sum(order_amount)                      as revenue_reached,
        avg(order_amount)                      as avg_amount,
        null::number(10,2)                     as avg_days_from_created
    from orders

    union all

    -- "Paid" — pedidos que tiveram evento de paid
    select
        2                                      as funnel_step,
        'paid'                                 as status_name,
        count(*)                               as orders_reached,
        sum(order_amount)                      as revenue_reached,
        avg(order_amount)                      as avg_amount,
        avg(days_to_paid)                      as avg_days_from_created
    from orders
    where paid_date_key is not null

    union all

    -- "Shipped"
    select
        3                                      as funnel_step,
        'shipped'                              as status_name,
        count(*)                               as orders_reached,
        sum(order_amount)                      as revenue_reached,
        avg(order_amount)                      as avg_amount,
        avg(days_to_shipped)                   as avg_days_from_created
    from orders
    where shipped_date_key is not null

    union all

    -- "Delivered"
    select
        4                                      as funnel_step,
        'delivered'                            as status_name,
        count(*)                               as orders_reached,
        sum(order_amount)                      as revenue_reached,
        avg(order_amount)                      as avg_amount,
        avg(days_to_delivered)                 as avg_days_from_created
    from orders
    where delivered_date_key is not null
),

-- ---------------------------------------------------------------------
-- Combina com totais para calcular taxas
-- ---------------------------------------------------------------------
final as (
    select
        sm.funnel_step,
        sm.status_name,
        sm.orders_reached,
        sm.revenue_reached,
        round(sm.avg_amount, 2)                                     as avg_amount,
        round(sm.avg_days_from_created, 2)                          as avg_days_from_created,
        
        -- Taxa de conversao em relacao ao topo (created)
        round(sm.orders_reached * 1.0 / t.total_orders, 4)         as conversion_rate,
        
        -- Drop-off em relacao ao step anterior
        sm.orders_reached 
            - lag(sm.orders_reached) over (order by sm.funnel_step) as orders_dropped_from_previous,

        -- Auditoria
        current_timestamp() as dbt_computed_at

    from status_metrics sm
    cross join totals t
)

select * from final
order by funnel_step