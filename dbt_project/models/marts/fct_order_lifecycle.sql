{{ config(materialized='table') }}

{# 
    fct_order_lifecycle — transactional fact com 1 linha por status change.
    
    Granularidade: 1 linha por evento (event_id unico).
    Source: stg_orders_status_changed enriquecido com FKs e atributos
    do pedido base (amount, customer_id).
    
    Permite analise de:
    - Tempo entre transicoes
    - Funil de conversao
    - Distribuicao temporal de mudancas
#}

with status_changes as (
    select * from {{ ref('stg_orders_status_changed') }}
),

orders as (
    select * from {{ ref('stg_orders_created') }}
),

-- ---------------------------------------------------------------------
-- Enriquece status changes com atributos do pedido
-- ---------------------------------------------------------------------
final as (
    select
        -- Surrogate key do evento
        md5(sc.event_id) as lifecycle_sk,

        -- Identificadores
        sc.event_id,
        sc.order_id,

        -- Foreign keys
        md5(o.order_id)                                    as order_sk,
        md5(o.customer_id)                                 as customer_sk,
        cast(to_char(sc.changed_at, 'YYYYMMDD') as integer) as changed_date_key,
        cast(to_char(o.created_at, 'YYYYMMDD') as integer)  as created_date_key,

        -- Atributos da transicao
        sc.old_status,
        sc.new_status,

        -- Tempo
        sc.changed_at,
        o.created_at as order_created_at,

        -- Metricas derivadas
        datediff('day', o.created_at, sc.changed_at)   as days_since_creation,
        datediff('hour', o.created_at, sc.changed_at)  as hours_since_creation,
        
        -- Atributos do pedido (denormalizados para facilitar queries)
        o.customer_id,
        o.amount as order_amount,
        o.currency,
        o.item_count,

        -- Auditoria
        current_timestamp() as dbt_computed_at

    from status_changes sc
    inner join orders o on sc.order_id = o.order_id
)

select * from final