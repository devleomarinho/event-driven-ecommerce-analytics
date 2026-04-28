# Runbook 05: Deploy de migrations com schemachange

Como executar deploys de migrations Snowflake nos três ambientes (DEV, QA, PROD)
usando schemachange. Cobre o fluxo dia a dia: deploy local em DEV durante
desenvolvimento, e promoção para QA e PROD.

## Pré-requisitos

- [Runbook 02](02-configure-local-environment.md) concluído (schemachange
  instalado, key-pair configurado, `load-env.ps1` funcionando)
- Database de cada ambiente já criado em V001 (validar com
  `SHOW DATABASES LIKE 'ANALYTICS_%'` no Snowsight)

## Conceitos essenciais

### Estrutura dos arquivos

```text
infra/snowflake/
├── environments/
│   ├── dev.yml      # config para ambiente DEV (database_name=ANALYTICS_DEV)
│   ├── qa.yml       # config para ambiente QA  (database_name=ANALYTICS_QA)
│   └── prod.yml     # config para ambiente PROD (database_name=ANALYTICS_PROD)
└── migrations/
    ├── V001__warehouses_databases_schemas.sql
    ├── V002__rbac_roles.sql
    └── ...
```

Cada arquivo `<env>.yml` define:

- `change-history-table`: tabela onde o histórico de migrations é registrado
  (uma por ambiente: `CHANGE_HISTORY_DEV`, `CHANGE_HISTORY_QA`, `CHANGE_HISTORY_PROD`)
- `vars`: variáveis Jinja injetadas nos SQLs (`{{ database_name }}`, `{{ env }}`)

### Tipos de script

- `V<n>__<descricao>.sql`: **versioned**. Roda uma única vez por ambiente.
  Histórico permanente. **Não editar após primeiro deploy bem-sucedido.**
- `R__<descricao>.sql`: **repeatable**. Roda sempre que o conteúdo muda
  (detecção via hash). Para views, procedures, scripts idempotentes.
- `A__<descricao>.sql`: **always**. Roda em toda execução. Raro.

### Idempotência

Migrations já aplicadas são puladas em deploys subsequentes. Rodar
`schemachange deploy` várias vezes é seguro — só executa o que ainda não
foi aplicado.

## Fluxo dia a dia

### 1. Carregar variáveis de ambiente

```powershell
. .\scripts\load-env.ps1
```

Validar:

```powershell
$env:SNOWFLAKE_ACCOUNT
# Deve imprimir o account identifier
```

### 2. Criar nova migration

Criar arquivo seguindo o padrão de nomenclatura no diretório `migrations/`:

```
infra/snowflake/migrations/V006__bronze_table_and_pipe.sql
```

Numeração: incrementar a partir do último V existente. Não pular números.

Conteúdo do SQL pode usar Jinja para parametrização:

```sql
CREATE TABLE IF NOT EXISTS {{ database_name }}.BRONZE.RAW_EVENTS (
    ...
);
```

### 3. Validar com `--dry-run` antes de aplicar

```powershell
schemachange deploy `
    --config-folder ./infra/snowflake/environments `
    --config-file-name dev.yml `
    --dry-run
```

O dry-run conecta no Snowflake, valida sintaxe SQL via parsing, mas **não
executa** mudanças. Erros aparecem nesta fase.

### 4. Deploy real em DEV

Remover o `--dry-run`:

```powershell
schemachange deploy `
    --config-folder ./infra/snowflake/environments `
    --config-file-name dev.yml
```

Saída esperada (exemplo para uma migration nova V006):

```
Applying V (006) SQL change script
scripts_applied=1 scripts_skipped=5
```

`skipped=5` indica que V001-V005 foram detectadas como já aplicadas e puladas.

### 5. Validar no Snowsight

```sql
SELECT version, script, status, installed_on
FROM METADATA.SCHEMACHANGE.CHANGE_HISTORY_DEV
ORDER BY installed_on DESC;
```

A migration recém-aplicada deve aparecer com `status='Success'`.

### 6. Promoção para QA e PROD

Após validar em DEV, promover trocando o config:

```powershell
# Deploy em QA
schemachange deploy `
    --config-folder ./infra/snowflake/environments `
    --config-file-name qa.yml

# Deploy em PROD
schemachange deploy `
    --config-folder ./infra/snowflake/environments `
    --config-file-name prod.yml
```

Em CI/CD via GitHub Actions, esses deploys são automatizados:

- Merge em `develop` → deploy automático em QA
- Merge em `main` → deploy automático em PROD (com aprovação manual via
  Environment Protection)

## Lidando com migrations falhas

Se uma migration falha durante o deploy, o schemachange registra como
`status='Failed'` na CHANGE_HISTORY. A migration não é considerada aplicada,
mas o registro fica gravado com o hash do arquivo.

Para corrigir e re-aplicar:

```sql
-- Confirmar que a falha está registrada
SELECT version, script, status, installed_on
FROM METADATA.SCHEMACHANGE.CHANGE_HISTORY_DEV
WHERE status = 'Failed';

-- Remover o registro da falha (a migration em si não foi aplicada,
-- só o registro precisa sair para o schemachange tentar de novo)
DELETE FROM METADATA.SCHEMACHANGE.CHANGE_HISTORY_DEV
WHERE version = '<versao>' AND status = 'Failed';
```

Corrigir o SQL no arquivo da migration, salvar, e re-deployar normalmente.

Esse é um dos poucos casos em que se modifica um arquivo de migration **antes**
do primeiro deploy bem-sucedido. Após sucesso, o arquivo é imutável.

## Comandos úteis para diagnóstico

```bash
# Listar migrations existentes na pasta
ls infra/snowflake/migrations/

# Ver versão do schemachange
schemachange --version

# Validar config sem conectar
schemachange deploy --config-folder ... --config-file-name dev.yml --dry-run -v

# Ver todas as flags disponíveis
schemachange deploy --help
```

## Padrões de nomenclatura

```
V<numero>__<descricao_em_snake_case>.sql
```

Exemplos:

```
V001__warehouses_databases_schemas.sql
V002__rbac_roles.sql
V003__rbac_grants.sql
V004__storage_integrations.sql
V005__notification_integrations.sql
V006__bronze_table_and_pipe.sql
V007__silver_dynamic_tables.sql
```

Convenções:

- Numeração de 3 dígitos com padding (V001, não V1) — mantém ordenação
  alfabética e numérica alinhadas.
- Descrição em `snake_case` minúsculo, conciso (até 50 caracteres).
- Dois underscores `__` separando o número da descrição (sintaxe do schemachange).
- Sem espaços, hífens, ou caracteres especiais.

## Troubleshooting

**Erro: `Connection default is not configured`**

Causa: schemachange não está lendo as variáveis de ambiente.

Fix: confirmar que rodou `. .\scripts\load-env.ps1` na sessão atual.
Validar com `$env:SNOWFLAKE_ACCOUNT`.

**Erro: `Script checksum has drifted since application`**

Causa: arquivo de migration foi modificado **após** ter sido aplicado com
sucesso. O schemachange detecta via hash.

Fix: nunca modificar migration aplicada. Criar nova migration com `ALTER`
para fazer a correção. Se for absolutamente necessário (ambiente de
desenvolvimento, primeiro deploy), apagar o registro da `CHANGE_HISTORY_*`
para forçar re-aplicação.

**Erro: `Object does not exist, or operation cannot be performed`**

Causa: ROLE_DEPLOY não tem privilégio na operação. Comum em migrations
que criam Storage/Notification Integrations.

Fix: confirmar que `GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE ROLE_DEPLOY`
foi executado (ver Runbook 01).

**Erro: `Unable to find change history table`**

Causa: schema `METADATA.SCHEMACHANGE` não existe, ou o nome configurado
em `change-history-table` está errado no YAML.

Fix: validar com `SHOW SCHEMAS IN DATABASE METADATA`. Se o schema não existe,
voltar ao Runbook 01 (Passo 1 cria o schema).

**Migration aplicada com sucesso mas objeto não foi criado no Snowflake**

Causa: SQL foi sintaticamente válido, mas executado em contexto errado
(database/schema diferente do esperado).

Fix: revisar o SQL — geralmente falta um `USE DATABASE {{ database_name }}`
ou referência fully-qualified como `{{ database_name }}.SCHEMA.OBJETO`.

## Próximos passos

- [Runbook 06 — Troubleshooting geral](06-troubleshooting.md)