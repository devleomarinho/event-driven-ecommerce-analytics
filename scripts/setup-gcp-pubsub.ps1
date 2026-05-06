# scripts/setup-gcp-pubsub.ps1
# Configura Pub/Sub subscription + GCS notification para um ambiente.
# Idempotente: pode ser rodado multiplas vezes sem efeito colateral.
#
# Uso:
#   .\scripts\setup-gcp-pubsub.ps1 -Environment qa
#   .\scripts\setup-gcp-pubsub.ps1 -Environment prod

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("qa", "prod")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------
# Configuracao derivada do ambiente
# -----------------------------------------------------------------
$Project     = "event-driven-snowflake"
$Bucket      = "raw-events-$Environment"
$NotifyTopic = "gcs-notify-events-$Environment"
$NotifySub   = "gcs-notify-events-$Environment-snowflake"

Write-Host "=========================================="  -ForegroundColor Cyan
Write-Host "  Setup Pub/Sub + GCS - env: $Environment"   -ForegroundColor Cyan
Write-Host "=========================================="  -ForegroundColor Cyan

# -----------------------------------------------------------------
# 1. Pub/Sub Subscription PULL para o Snowflake
#
#    --ack-deadline=600s: Snowflake precisa de ~10min para o COPY
#    --message-retention-duration=7d: backlog em caso de outage
# -----------------------------------------------------------------
Write-Host ""
Write-Host "[1/2] Subscription PULL para Snowflake" -ForegroundColor Yellow

gcloud pubsub subscriptions describe $NotifySub --project=$Project 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  -> Subscription '$NotifySub' ja existe, pulando" -ForegroundColor Gray
}
else {
    Write-Host "  -> Criando subscription '$NotifySub'..."
    gcloud pubsub subscriptions create $NotifySub `
        --project=$Project `
        --topic=$NotifyTopic `
        --ack-deadline=600 `
        --message-retention-duration=7d

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falha ao criar subscription"
        exit 1
    }
    Write-Host "  -> Subscription criada" -ForegroundColor Green
}

# -----------------------------------------------------------------
# 2. GCS Notification: bucket -> topico
#
#    --object-prefix=events/ filtra so uploads sob /events/
# -----------------------------------------------------------------
Write-Host ""
Write-Host "[2/2] GCS Notification: bucket -> topico" -ForegroundColor Yellow

$existingNotifications = gcloud storage buckets notifications list "gs://$Bucket" --format=json 2>$null | ConvertFrom-Json

$alreadyConfigured = $false
if ($existingNotifications) {
    foreach ($notif in $existingNotifications) {
        if ($notif.topic -like "*$NotifyTopic*") {
            $alreadyConfigured = $true
            break
        }
    }
}

if ($alreadyConfigured) {
    Write-Host "  -> Notification para '$NotifyTopic' ja existe, pulando" -ForegroundColor Gray
}
else {
    Write-Host "  -> Criando GCS notification..."
    gcloud storage buckets notifications create "gs://$Bucket" `
        --topic=$NotifyTopic `
        --event-types=OBJECT_FINALIZE `
        --payload-format=json `
        --object-prefix=events/

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Falha ao criar GCS notification"
        exit 1
    }
    Write-Host "  -> Notification criada" -ForegroundColor Green
}

# -----------------------------------------------------------------
# 3. Validacao final
# -----------------------------------------------------------------
Write-Host ""
Write-Host "[Validacao] Estado final:" -ForegroundColor Yellow

Write-Host ""
Write-Host "  Subscription:"
gcloud pubsub subscriptions describe $NotifySub --project=$Project --format=json | ConvertFrom-Json | Format-List name, topic, ackDeadlineSeconds

Write-Host ""
Write-Host "  Notifications no bucket:"
gcloud storage buckets notifications list "gs://$Bucket" --format=json | ConvertFrom-Json | Format-Table id, topic, event_types, payload_format

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Setup completo para $Environment"        -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green