# Runbook 09 — Operação do dbt no Workspace

## Visão geral

Este runbook cobre o ciclo de vida do dbt em desenvolvimento e
deploy via Workspace do Snowsight. Pré-requisito: Runbook 08 completo.

## Workflow de desenvolvimento padrão

### 1. Iteração local

No Workspace:

1. Toolbar superior: seleciona branch (geralmente develop ou feature/...)
2. Edita .sql ou .yml diretamente no IDE
3. Para validar sintaxe sem rodar:
   - Toolbar dbt → Command: `parse` → Run
4. Para testar um modelo específico:
   - Toolbar dbt → Command: `run --select <model>` → Target: dev → Run
5. Verificar resultado em ANALYTICS_DEV.GOLD.<model>

### 2. Commit e push

Feito direto no Workspace:

1. Painel Git (lateral esquerda)
2. Selecionar arquivos a commitar
3. Mensagem de commit
4. "Commit and Push"

### 3. Deploy em QA

Após commit, no Workspace:

1. Sync changes (puxa próprio commit do Git)
2. Toolbar dbt → Target: qa
3. Comando: `build --target qa` → Run
4. Aguardar — output mostra quantos modelos rodaram e quantos testes passaram

### 4. Deploy em PROD

Após validação em QA:

1. Cria PR de develop → main no GitHub
2. Aprova e merge
3. Workspace conectado a main automaticamente puxa
4. Toolbar dbt → Target: prod
5. Comando: `build --target prod` → Run

## Comandos úteis

| Comando | Uso |
|---|---|
| `dbt parse` | Valida sintaxe de todos os modelos |
| `dbt compile` | Gera o SQL final (sem executar) |
| `dbt run --select staging` | Roda só camada staging |
| `dbt run --select +fct_orders` | Roda fct_orders e tudo upstream |
| `dbt test --select dim_customers` | Só testes desse modelo |
| `dbt build --select marts` | Run + test em toda camada marts |
| `dbt seed` | Carrega CSVs em /seeds/ |

## Limitações conhecidas

### `dbt deps` em conta trial

A conta atual é trial, que não permite External Access Integration.
Para `dbt deps` (download de packages externos como dbt_utils),
seria necessário upgrade para conta Standard.

**Workaround:** projeto não usa packages externos. Se precisar adicionar,
upgrade necessário.

### CI/CD do dbt

Por limitação acima, `EXECUTE DBT PROJECT` via GitHub Actions não foi
implementado. dbt é rodado manualmente no Workspace.

Em conta Standard+, o pattern seria:

\`\`\`yaml
# .github/workflows/dbt-deploy.yml (futuro)
- run: |
    snow sql -q "ALTER GIT REPOSITORY ... FETCH;"
    snow dbt deploy ...
    snow dbt execute ... --args "build --target qa"
\`\`\`

## Troubleshooting

### "Configuration paths exist that do not apply to any resources"

dbt detecta config para um modelo que não existe ainda. Não é erro,
só warning. Aparece quando dbt_project.yml declara configs para
arquivos que ainda não foram criados.

### "Model X depends on model Y which does not exist"

Ordem de criação errada. Crie modelos em ordem topológica:
sources → staging → dimensions → facts → marts.

### Workspace mostra arquivo desatualizado

Sync do Git pode demorar. Force refresh:

1. Painel Git → Pull
2. Aguarda 10-30s
3. Reload do Workspace