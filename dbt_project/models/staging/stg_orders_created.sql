{{ config(materialized='view') }}

WITH source as (
    SELECT * FROM {{source('silver', 'dt_orders_created')}}
),

renamed as (
    SELECT
        event_id,
        order_id,
        customer_id,
        event_timestamp as created_at,
        amount,
        currency,
        item_count,
        _ingested_at as ingested_at
    FROM source
)

SELECT * FROM renamed