# Runbook 08 — Setup do dbt Projects on Snowflake

## Contexto

Este runbook descreve como configurar dbt Projects on Snowflake do zero
para executar a camada Gold deste projeto. Pré-requisitos: schemachange
V001-V007 já aplicado em todos os ambientes.

## Pré-requisitos da conta Snowflake

### 1. Habilitar Personal Database

Workspaces dependem de Personal Database, que é desabilitado por padrão.

\`\`\`sql
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET ENABLE_PERSONAL_DATABASE = TRUE;
\`\`\`

### 2. Habilitar secondary roles para o usuário

\`\`\`sql
ALTER USER LEONARDO SET DEFAULT_SECONDARY_ROLES = ('ALL');
ALTER USER SVC_DEPLOY SET DEFAULT_SECONDARY_ROLES = ('ALL');
\`\`\`

Substitua os nomes pelos usuários reais.

## Configuração de integração com GitHub

### Pré-requisito no GitHub

Personal Access Token (PAT) com permissão de Read & Write em **Contents**
do repositório. Veja seção "Configuração do PAT" abaixo para passos detalhados.

### Criar Secret no Snowflake

\`\`\`sql
USE ROLE ACCOUNTADMIN;
USE DATABASE METADATA;
CREATE SCHEMA IF NOT EXISTS GIT_INTEGRATIONS;
USE SCHEMA GIT_INTEGRATIONS;

CREATE OR REPLACE SECRET GITHUB_PAT_<USERNAME>
    TYPE = PASSWORD
    USERNAME = '<github_username>'
    PASSWORD = 'github_pat_xxxxxxxxxxxxxxxxxxxx'
    COMMENT = 'PAT para acessar repositórios do <username>';
\`\`\`

### Criar API Integration

\`\`\`sql
CREATE OR REPLACE API INTEGRATION GITHUB_INT_<USERNAME>
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/<username>/')
    ALLOWED_AUTHENTICATION_SECRETS = (METADATA.GIT_INTEGRATIONS.GITHUB_PAT_<USERNAME>)
    ENABLED = TRUE;
\`\`\`

### Permissões para ROLE_TRANSFORMER

\`\`\`sql
GRANT USAGE ON INTEGRATION GITHUB_INT_<USERNAME> TO ROLE ROLE_TRANSFORMER;
GRANT READ ON SECRET METADATA.GIT_INTEGRATIONS.GITHUB_PAT_<USERNAME> TO ROLE ROLE_TRANSFORMER;
\`\`\`

### Criar Git Repository

\`\`\`sql
USE ROLE ROLE_TRANSFORMER;
USE DATABASE ANALYTICS_QA;
USE SCHEMA GOLD;

CREATE OR REPLACE GIT REPOSITORY REPO_EVENT_DRIVEN_ANALYTICS
    API_INTEGRATION = GITHUB_INT_<USERNAME>
    GIT_CREDENTIALS = METADATA.GIT_INTEGRATIONS.GITHUB_PAT_<USERNAME>
    ORIGIN = 'https://github.com/<username>/event-driven-ecommerce-analytics.git';
\`\`\`

### Validar conexão

\`\`\`sql
ALTER GIT REPOSITORY REPO_EVENT_DRIVEN_ANALYTICS FETCH;
LS @REPO_EVENT_DRIVEN_ANALYTICS/branches/main;
\`\`\`

Esperado: lista o conteúdo do repo. Se falhar, diagnosticar IAM e PAT.

## Configuração do PAT no GitHub

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Generate new token:
   - Repository access: Only select repositories → seu repo
   - Repository permissions:
     - Contents: Read and write
     - Metadata: Read
   - Expiration: 90 dias (recomendado)
3. Copia o token (formato github_pat_...)
4. Use o valor no comando CREATE SECRET acima

## Criação do Workspace no Snowsight

1. Snowsight → Projects → Workspaces → "+ Workspace"
2. Selecione "Create from Git Repository"
3. Configure:
   - **API Integration:** GITHUB_INT_<username>
   - **Secret:** METADATA.GIT_INTEGRATIONS.GITHUB_PAT_<username>
   - **Repository URL:** https://github.com/<username>/event-driven-ecommerce-analytics
   - **Branch:** main (ou develop para iteração)
   - **Subfolder:** dbt_project/ (onde mora o projeto dbt)
4. Selecione o database/schema padrão: ANALYTICS_DEV.GOLD
5. Workspace criado e conectado ao Git

## Validação final

Dentro do Workspace:

1. Abra dbt_project.yml — confirma que aparece o conteúdo do repo
2. Toolbar dbt → seleciona target = "qa"
3. Roda comando: `dbt parse`
4. Esperado: encontra 4 sources, 7 models (4 staging + 4 dim/fact + 2 marts), e ~30 tests

Se passar, ambiente está pronto para deploy completo.