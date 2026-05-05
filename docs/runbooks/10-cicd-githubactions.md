# Runbook 10 — CI/CD com GitHub Actions

## Visão geral

O projeto usa GitHub Actions para automatizar dois fluxos:

1. **Schemachange** — deploy de migrations Snowflake
2. **Cloud Run Job** — build de imagem e deploy do gerador de eventos

O dbt é executado manualmente via Workspace Snowsight (ver Runbook 09).

## Estratégia de branches

\`\`\`
feature/*   →  push  →  deploy em DEV
develop     →  merge →  deploy em QA
main        →  merge →  deploy em PROD (requer approval manual)
\`\`\`

## Workflows

### schemachange-deploy

Dispara em mudanças em `infra/snowflake/**`.

Aplica migrations versionadas via schemachange CLI no ambiente correspondente.

**Trigger manual:** Actions → schemachange-deploy → Run workflow → escolhe target.

## Configuração inicial (uma vez)

### Secrets do GitHub

Configurar em Settings → Secrets and variables → Actions:

| Secret | Descrição |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Identificador da conta Snowflake |
| `SNOWFLAKE_USER` | Usuário de service account (ex: SVC_DEPLOY) |
| `SNOWFLAKE_ROLE` | Role default (ex: ROLE_DEPLOY) |
| `SNOWFLAKE_WAREHOUSE` | Warehouse para schemachange (ex: WH_DEPLOY_XS) |
| `SNOWFLAKE_PRIVATE_KEY` | Chave privada RSA em base64 |
| `GCP_SA_KEY` | JSON do service account do GitHub Actions |

### Gerar SNOWFLAKE_PRIVATE_KEY

\`\`\`powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$env:USERPROFILE\.snowflake\keys\<service_account_key>.p8")) | Set-Clipboard
\`\`\`

Cola no Secret.

### Environment Protection

Em Settings → Environments:

- `dev` — sem proteções
- `qa` — sem proteções
- `prod` — required reviewers (adicionar seu user)

## Operação

### Deploy normal

1. Cria branch: `git checkout -b feature/nova-migration`
2. Faz mudanças em `infra/snowflake/migrations/V008__...sql`
3. Commit e push
4. GitHub Actions detecta e roda em DEV
5. Cria PR para develop
6. Merge → roda em QA
7. Validação manual em QA (testes, dados)
8. PR de develop para main
9. Merge → aguarda approval em prod → deploy

### Deploy manual (hotfix)

1. Actions → schemachange-deploy ou cloud-run-job-deploy
2. "Run workflow"
3. Seleciona branch e target
4. Run

### Verificar status

Actions tab do GitHub mostra histórico de execuções, logs detalhados, e tempos.

## Troubleshooting

### Schemachange falha com "Pipe ... already exists, but current role has no privileges"

Objeto criado fora do schemachange (ex: sandbox manual) com ownership de role diferente. Transferir ownership:

\`\`\`sql
GRANT OWNERSHIP ON PIPE <name> TO ROLE ROLE_INGESTION REVOKE CURRENT GRANTS;
\`\`\`

### Deploy em PROD trava em "Waiting for approval"

Configuração de Environment Protection. Acessa o run em Actions → clica em "Review deployments" → aprova ou rejeita.


## Limitações conhecidas

- **dbt Projects on Snowflake** não automatizado (limitação de conta trial). Plano: migrar para CI/CD do dbt em conta Standard+.
- **Schedule do Cloud Run Job** não automatizado. Em produção real, configurar Cloud Scheduler.
- **Rollback automatizado** não implementado. Em caso de falha em PROD, rollback manual via Actions (deploy de versão anterior).