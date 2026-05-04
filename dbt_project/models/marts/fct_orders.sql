{{ config(materialized='table') }}

{# 
    fct_orders — snapshot fact com estado atual de cada pedido.
    
    Granularidade: 1 linha por order_id.
    Source: stg_orders_created + stg_orders_status_changed.
    
    Logica:
    1. CTE 'orders' pega base de pedidos criados.
    2. CTE 'last_status' pega ultima transicao por order_id.
    3. CTE 'status_dates' extrai data de cada transicao especifica
       (paid, shipped, delivered) para metricas de SLA.
    4. final faz LEFT JOIN — pedidos sem status changes mantem 'created'.
#}

with orders as (
    select * from {{ ref('stg_orders_created') }}
),

status_changes as (
    select * from {{ ref('stg_orders_status_changed') }}
),

-- ---------------------------------------------------------------------
-- Ultima transicao de status por order_id
-- ---------------------------------------------------------------------
last_status as (
    select
        order_id,
        new_status as current_status,
        changed_at as last_status_changed_at
    from status_changes
    qualify row_number() over (
        partition by order_id
        order by changed_at desc
    ) = 1
),

-- ---------------------------------------------------------------------
-- Datas de cada transicao especifica (para metricas de SLA)
-- ---------------------------------------------------------------------
paid_dates as (
    select
        order_id,
        changed_at as paid_at
    from status_changes
    where new_status = 'paid'
    qualify row_number() over (
        partition by order_id
        order by changed_at asc
    ) = 1
),

shipped_dates as (
    select
        order_id,
        changed_at as shipped_at
    from status_changes
    where new_status = 'shipped'
    qualify row_number() over (
        partition by order_id
        order by changed_at asc
    ) = 1
),

delivered_dates as (
    select
        order_id,
        changed_at as delivered_at
    from status_changes
    where new_status = 'delivered'
    qualify row_number() over (
        partition by order_id
        order by changed_at asc
    ) = 1
),

-- ---------------------------------------------------------------------
-- Final: agrega tudo em 1 linha por order_id
-- ---------------------------------------------------------------------
final as (
    select
        -- Surrogate key do fato (estavel no order_id)
        md5(o.order_id) as order_sk,

        -- Dimensao degenerada
        o.order_id,

        -- Foreign keys (joins com dimensoes)
        md5(o.customer_id) as customer_sk,
        cast(to_char(o.created_at, 'YYYYMMDD') as integer) as created_date_key,
        cast(to_char(p.paid_at, 'YYYYMMDD') as integer)        as paid_date_key,
        cast(to_char(s.shipped_at, 'YYYYMMDD') as integer)     as shipped_date_key,
        cast(to_char(d.delivered_at, 'YYYYMMDD') as integer)   as delivered_date_key,

        -- Atributos do pedido
        coalesce(ls.current_status, 'created') as current_status,

        -- Metricas (medidas agregaveis)
        o.amount as order_amount,
        o.currency,
        o.item_count,

        -- Timestamps de eventos
        o.created_at,
        p.paid_at,
        s.shipped_at,
        d.delivered_at,
        ls.last_status_changed_at,

        -- Metricas derivadas (SLAs)
        datediff('day', o.created_at, p.paid_at)     as days_to_paid,
        datediff('day', o.created_at, s.shipped_at)  as days_to_shipped,
        datediff('day', o.created_at, d.delivered_at) as days_to_delivered,

        -- Flags utilitarias
        case when d.delivered_at is not null then true else false end as is_delivered,
        case when ls.current_status in ('delivered', 'canceled') then true else false end as is_completed,

        -- Timestamp de quando este pedido foi computado pelo dbt (para audit)
        current_timestamp() as dbt_computed_at

    from orders o
    left join last_status     ls on o.order_id = ls.order_id
    left join paid_dates       p on o.order_id = p.order_id
    left join shipped_dates    s on o.order_id = s.order_id
    left join delivered_dates  d on o.order_id = d.order_id
)

select * from final