# Runbook 01: Bootstrap inicial do Snowflake

Cria os recursos mínimos no Snowflake necessários para que o `schemachange`
possa assumir o controle das migrations daqui em diante: usuário de serviço,
role de deploy, warehouse, database de metadata, e autenticação por chave RSA.

Este é o único runbook que executa SQL manualmente no Snowsight. Tudo
o que vem depois passa a ser deploy automatizado.

## Pré-requisitos

- Conta Snowflake (Enterprise edition recomendada — Standard não tem Dynamic Tables)
- Acesso à role `ACCOUNTADMIN` na conta
- OpenSSL disponível no terminal (Git Bash ou Linux/macOS já trazem)

## Passo 1 — Criar a infraestrutura mínima

No Snowsight, logado como `ACCOUNTADMIN`, executar:

```sql
USE ROLE ACCOUNTADMIN;

-- Role de deploy (será assumida pelo schemachange)
CREATE ROLE IF NOT EXISTS ROLE_DEPLOY
    COMMENT = 'Role usada pelo schemachange para aplicar migrations';

-- Hierarquia: ROLE_DEPLOY herda SYSADMIN + SECURITYADMIN.

GRANT ROLE SYSADMIN      TO ROLE ROLE_DEPLOY;
GRANT ROLE SECURITYADMIN TO ROLE ROLE_DEPLOY;

-- Privilégio account-level específico para criar Storage/Notification
-- Integrations (necessário em V004/V005). Sem isso, exigiria ACCOUNTADMIN.
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE ROLE_DEPLOY;

-- Warehouse exclusivo para o schemachange.
-- XS é suficiente
CREATE WAREHOUSE IF NOT EXISTS WH_DEPLOY_XS
    WITH WAREHOUSE_SIZE = 'XSMALL'
         AUTO_SUSPEND = 60
         AUTO_RESUME = TRUE
         INITIALLY_SUSPENDED = TRUE
         STATEMENT_TIMEOUT_IN_SECONDS = 600
         COMMENT = 'Warehouse exclusivo do schemachange (CI/CD)';

GRANT USAGE ON WAREHOUSE WH_DEPLOY_XS TO ROLE ROLE_DEPLOY;

-- Database para metadata do schemachange.
-- A tabela CHANGE_HISTORY (uma por ambiente) viverá em METADATA.SCHEMACHANGE.
CREATE DATABASE IF NOT EXISTS METADATA
    COMMENT = 'Metadata: schemachange history, operational views';

GRANT OWNERSHIP ON DATABASE METADATA TO ROLE ROLE_DEPLOY;

-- Schema dedicado para o schemachange
CREATE SCHEMA IF NOT EXISTS METADATA.SCHEMACHANGE
    COMMENT = 'Histórico de migrations aplicadas via schemachange';

GRANT OWNERSHIP ON SCHEMA METADATA.SCHEMACHANGE
    TO ROLE ROLE_DEPLOY REVOKE CURRENT GRANTS;

-- Mantém USAGE em PUBLIC para a role default não quebrar
GRANT USAGE ON SCHEMA METADATA.PUBLIC TO ROLE ROLE_DEPLOY;
```

## Passo 2 — Criar o usuário de serviço

```sql
CREATE USER IF NOT EXISTS SVC_DEPLOY
    DEFAULT_ROLE      = ROLE_DEPLOY
    DEFAULT_WAREHOUSE = WH_DEPLOY_XS
    DEFAULT_NAMESPACE = 'METADATA.SCHEMACHANGE'
    COMMENT           = 'Service account: schemachange CI/CD (GitHub Actions)';
    -- PASSWORD intencionalmente ausente: autenticação 100% via key-pair.

GRANT ROLE ROLE_DEPLOY TO USER SVC_DEPLOY;
```

A ausência de `PASSWORD` é proposital. Sem senha, o usuário só pode autenticar
via chave RSA (próximo passo). Tentativa de login no Snowsight com este usuário
falha automaticamente — blindagem contra uso interativo indevido.

## Passo 3 — Gerar o par de chaves RSA

No terminal local (Git Bash no Windows, ou bash/zsh em Linux/macOS):

```bash
mkdir -p ~/.snowflake/keys
chmod 700 ~/.snowflake/keys

# Chave privada PKCS#8 não-criptografada
openssl genrsa 2048 \
    | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/keys/svc_deploy_rsa_key.p8 -nocrypt

# Chave pública correspondente
openssl rsa -in ~/.snowflake/keys/svc_deploy_rsa_key.p8 \
    -pubout -out ~/.snowflake/keys/svc_deploy_rsa_key.pub

# Permissões restritas (Linux/macOS)
chmod 600 ~/.snowflake/keys/svc_deploy_rsa_key.p8
chmod 644 ~/.snowflake/keys/svc_deploy_rsa_key.pub
```

No Windows (após gerar via Git Bash), aplicar permissões via PowerShell:

```powershell
icacls "$env:USERPROFILE\.snowflake\keys\svc_deploy_rsa_key.p8" /inheritance:r
icacls "$env:USERPROFILE\.snowflake\keys\svc_deploy_rsa_key.p8" /grant:r "${env:USERNAME}:F"
```

A chave privada nunca deve ser commitada. O `.gitignore` do projeto já bloqueia
`*.p8` por precaução, mas a primeira linha de defesa é guardar fora do diretório
do repo.

## Passo 4 — Registrar a chave pública no Snowflake

Extrair o conteúdo da chave pública (sem cabeçalho/rodapé):

```bash
grep -v 'PUBLIC KEY' ~/.snowflake/keys/svc_deploy_rsa_key.pub | tr -d '\n'
```

Copiar o output. No Snowsight, executar (substituindo o placeholder):

```sql
USE ROLE ACCOUNTADMIN;

ALTER USER SVC_DEPLOY SET RSA_PUBLIC_KEY = '<COLE_AQUI>';
```

Validar:

```sql
DESC USER SVC_DEPLOY;
-- Procurar a linha RSA_PUBLIC_KEY_FP — deve mostrar um hash SHA256.
```

## Validação final

A ponte entre o Snowflake e a máquina local pode ser testada com o Snowflake CLI.
Configurar uma conexão e testar:

```bash
snow connection test --connection portfolio_deploy_dev
```

Saída esperada com status `OK` em todos os checks. Se passar, o bootstrap está
completo e o `schemachange` consegue conectar via key-pair.

A configuração da conexão local (arquivo `config.toml`, variáveis de ambiente,
permissões no Windows) está descrita no
[Runbook 02 — Configuração do ambiente local](02-configure-local-environment.md).

## Troubleshooting

**Erro: `JWT token is invalid`**

Causa típica: chave pública registrada com quebras de linha indevidas. O
comando `tr -d '\n'` no Passo 4 é essencial.

Fix: regerar a string da chave pública e refazer o `ALTER USER`.

**Erro: `User is empty or disabled`**

Causa: SVC_DEPLOY não foi criado, ou foi desabilitado depois.

Fix: `SHOW USERS LIKE 'SVC_DEPLOY';` para confirmar existência. Se ausente,
repetir Passo 2.

**Erro: `Role 'ROLE_DEPLOY' does not exist`**

Causa: a role não foi criada, ou o grant `ROLE_DEPLOY TO USER SVC_DEPLOY`
não foi executado.

Fix: rodar `SHOW ROLES LIKE 'ROLE_DEPLOY';` e `SHOW GRANTS TO USER SVC_DEPLOY;`
para diagnosticar. Refazer Passo 1 ou Passo 2 conforme o caso.

**Erro: `Insufficient privileges to operate on integration`**

Causa: ROLE_DEPLOY não recebeu `CREATE INTEGRATION ON ACCOUNT`.

Fix:
```sql
USE ROLE ACCOUNTADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE ROLE_DEPLOY;
```

## Próximos passos

- [Runbook 02 — Configuração do ambiente local](02-configure-local-environment.md)
- [Runbook 05 — Deploy de migrations](05-deploy-migrations.md)