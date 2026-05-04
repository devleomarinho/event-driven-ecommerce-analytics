{{ config(materialized='table') }}

{# 
   Gera tabela de calendario com 1 linha por dia, de 2024-01-01 ate 2027-12-31.
   
   Tecnica: GENERATOR(ROWCOUNT) cria N linhas vazias.
   Combinamos com SEQ4() (gerador sequencial 0-N) e DATEADD para
   criar uma sequencia de datas.
   
   Atributos pre-calculados evitam EXTRACT em todas as queries
   downstream. Joins em fct_orders.created_date_key = dim_date.date_key
   sao mais eficientes que filtros por substring/extract.
#}

with date_spine as (
    -- GENERATOR cria 1.461 linhas (4 anos * 365.25)
    -- SEQ4() retorna 0, 1, 2, ..., n para cada linha
    -- Comecamos em 2024-01-01 e adicionamos N dias
    select
        dateadd(
            'day',
            seq4(),
            '2024-01-01'::date
        ) as full_date
    from table(generator(rowcount => 1461))
),

filtered as (
    -- Filtra para nao passar de 2027-12-31
    -- (caso o calculo de dias inclua datas alem do range)
    select full_date
    from date_spine
    where full_date <= '2027-12-31'::date
),

enriched as (
    select
        -- Surrogate key no formato YYYYMMDD (integer)
        -- Vantagem: ordenavel, legivel, e leve para joins
        cast(to_char(full_date, 'YYYYMMDD') as integer) as date_key,
        
        -- Data crua
        full_date,
        
        -- Componentes basicos
        extract(year from full_date)         as year,
        extract(month from full_date)        as month,
        extract(day from full_date)          as day_of_month,
        extract(dayofyear from full_date)    as day_of_year,
        extract(week from full_date)         as week_of_year,
        extract(quarter from full_date)      as quarter,
        
        -- Semestre (Snowflake nao tem EXTRACT(SEMESTER))
        case 
            when extract(month from full_date) <= 6 then 1 
            else 2 
        end as semester,
        
        -- Dia da semana (Snowflake: 0=domingo, 6=sabado)
        extract(dayofweek from full_date) as day_of_week_number,
        
        -- Nomes textuais
        to_char(full_date, 'Day')   as day_name_full,    -- "Monday   "
        to_char(full_date, 'Dy')    as day_name_short,   -- "Mon"
        to_char(full_date, 'Month') as month_name_full,  -- "January  "
        to_char(full_date, 'Mon')   as month_name_short, -- "Jan"
        
        -- Booleanos uteis
        case 
            when extract(dayofweek from full_date) in (0, 6) then true 
            else false 
        end as is_weekend,
        
        case 
            when extract(dayofweek from full_date) in (0, 6) then false 
            else true 
        end as is_weekday,
        
        case 
            when extract(day from full_date) = 1 then true 
            else false 
        end as is_first_day_of_month,
        
        case 
            when full_date = last_day(full_date) then true 
            else false 
        end as is_last_day_of_month,
        
        -- Inicio e fim do mes (uteis para JOINs de "dados deste mes")
        date_trunc('month', full_date) as month_start_date,
        last_day(full_date)             as month_end_date,
        
        -- Inicio e fim do trimestre
        date_trunc('quarter', full_date) as quarter_start_date,
        
        -- Atributos compostos para drill-down em BI
        cast(to_char(full_date, 'YYYY-MM') as varchar)   as year_month,
        cast(to_char(full_date, 'YYYY-Q') as varchar)    as year_quarter

    from filtered
)

select * from enriched