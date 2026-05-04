{{ config(materialized='view') }}

with source as (
    select * from {{ source('silver', 'dt_orders_status_changed') }}
),

renamed as (
    select
        -- Identificadores
        event_id,
        order_id,

        -- Tempo
        event_timestamp as changed_at,

        -- Estados da transicao
        old_status,
        new_status,

        -- Auditoria
        _ingested_at as ingested_at
    from source
)

select * from renamed