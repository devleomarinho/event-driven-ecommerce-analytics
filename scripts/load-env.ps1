# scripts/load-env.ps1
$env:SNOWFLAKE_ACCOUNT         = "account-xyz"
$env:SNOWFLAKE_USER            = "user_deploy"
$env:SNOWFLAKE_ROLE            = "role_deploy"
$env:SNOWFLAKE_WAREHOUSE       = "WAREHOUSE_DEPLOY"
$env:SNOWFLAKE_AUTHENTICATOR   = "SNOWFLAKE_JWT"
$env:SNOWFLAKE_PRIVATE_KEY_PATH = "C:\keys\snowflake_key.p8"
Write-Host "Variáveis Snowflake carregadas no ambiente."