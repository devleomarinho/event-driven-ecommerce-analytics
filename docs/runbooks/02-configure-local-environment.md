# Runbook 02: Configuração do ambiente local

Configura a máquina local para autenticar no Snowflake via key-pair, executar
o `schemachange` contra os ambientes, e usar o Snowflake CLI para validações
ad-hoc. Cobre Windows (foco principal), com notas para Linux/macOS.

## Pré-requisitos

- [Runbook 01](01-bootstrap-snowflake.md) concluído (SVC_DEPLOY criado,
  chave RSA registrada)
- Python 3.10+ instalado
- Repositório clonado localmente

## Passo 1 — Instalar Snowflake CLI e schemachange

Instalar via `pipx` para isolar as ferramentas em virtualenvs próprios:

```bash
# pipx (uma vez)
python -m pip install --user pipx
python -m pipx ensurepath

# Fechar e reabrir o terminal antes de continuar

# Snowflake CLI (validações, smoke tests)
pipx install snowflake-cli-labs

# schemachange (deploy de migrations)
pipx install schemachange
```

Validar:

```bash
snow --version
schemachange --version
```

Ambos devem retornar versão sem erro.

## Passo 2 — Configurar o `config.toml` do Snowflake CLI

O `config.toml` é onde ficam as credenciais de conexão lidas pelo `snow`.
Localizar o arquivo (criar se não existir):

- Windows: `%USERPROFILE%\.snowflake\config.toml`
- Linux/macOS: `~/.snowflake/config.toml`

Conteúdo (substituir `<account>` pelo identifier do Snowflake):

```toml
default_connection_name = "portfolio_deploy_dev"

[connections.portfolio_deploy_dev]
account          = "<account>"
user             = "SVC_DEPLOY"
role             = "ROLE_DEPLOY"
warehouse        = "WH_DEPLOY_XS"
database         = "METADATA"
authenticator    = "SNOWFLAKE_JWT"
private_key_file = "C:\\Users\\<seu-usuario>\\.snowflake\\keys\\svc_deploy_rsa_key.p8"
```

Notas importantes:

- `default_connection_name` deve estar **antes** de qualquer `[connections.*]`,
  como chave de root-level do TOML.
- No Windows, usar barras duplas `\\` ou barras simples `/` no path. Nunca `\` simples.
- O `authenticator = "SNOWFLAKE_JWT"` é obrigatório para key-pair. Sem ele,
  o CLI assume password auth e pede senha (que não existe).
- Em Linux/macOS, o caminho fica como `/home/<user>/.snowflake/keys/svc_deploy_rsa_key.p8`.

## Passo 3 — Restringir permissões dos arquivos sensíveis (Windows)

O Snowflake CLI valida que `config.toml` não seja legível por outros usuários
do sistema. Sem isso, ele aborta operações em alguns fluxos.

No PowerShell:

```powershell
# config.toml
icacls "$env:USERPROFILE\.snowflake\config.toml" /inheritance:r
icacls "$env:USERPROFILE\.snowflake\config.toml" /grant:r "${env:USERNAME}:F"

# chave privada (defesa em profundidade)
icacls "$env:USERPROFILE\.snowflake\keys\svc_deploy_rsa_key.p8" /inheritance:r
icacls "$env:USERPROFILE\.snowflake\keys\svc_deploy_rsa_key.p8" /grant:r "${env:USERNAME}:F"
```

Em Linux/macOS, o equivalente é:

```bash
chmod 0600 ~/.snowflake/config.toml
chmod 0600 ~/.snowflake/keys/svc_deploy_rsa_key.p8
```

## Passo 4 — Validar a conexão

```bash
snow connection list
```

Deve listar `portfolio_deploy_dev` com `is_default = True`.

```bash
snow connection test
```

Saída esperada:

```
+---------------------+-------------------+
| key                 | value             |
|---------------------+-------------------|
| Connection name     | portfolio_deploy_dev |
| Status              | OK                |
| Host                | <account>...      |
| Account             | <account>         |
| User                | SVC_DEPLOY        |
| Role                | ROLE_DEPLOY       |
| Database            | METADATA          |
| Warehouse           | WH_DEPLOY_XS      |
+---------------------+-------------------+
```

Se algum campo não estiver `OK`, ver seção de troubleshooting abaixo.

## Passo 5 — Configurar variáveis de ambiente para o schemachange

O `schemachange` lê credenciais via variáveis de ambiente (não usa o `config.toml`
do `snow`). Para evitar definir manualmente a cada sessão, usar um script
parametrizado.

Em `scripts/load-env.ps1` (Windows):

```powershell
# scripts/load-env.ps1
# Carrega variáveis de ambiente do Snowflake na sessão atual.
# Uso: . .\scripts\load-env.ps1   (atenção ao ponto inicial — dot sourcing)

$env:SNOWFLAKE_ACCOUNT          = "<account>"
$env:SNOWFLAKE_USER             = "SVC_DEPLOY"
$env:SNOWFLAKE_ROLE             = "ROLE_DEPLOY"
$env:SNOWFLAKE_WAREHOUSE        = "WH_DEPLOY_XS"
$env:SNOWFLAKE_AUTHENTICATOR    = "SNOWFLAKE_JWT"
$env:SNOWFLAKE_PRIVATE_KEY_PATH = "$env:USERPROFILE\.snowflake\keys\svc_deploy_rsa_key.p8"

Write-Host "Variaveis Snowflake carregadas no ambiente."
```

Para Linux/macOS, equivalente em `scripts/load-env.sh`:

```bash
#!/usr/bin/env bash
# Uso: source scripts/load-env.sh

export SNOWFLAKE_ACCOUNT="<account>"
export SNOWFLAKE_USER="SVC_DEPLOY"
export SNOWFLAKE_ROLE="ROLE_DEPLOY"
export SNOWFLAKE_WAREHOUSE="WH_DEPLOY_XS"
export SNOWFLAKE_AUTHENTICATOR="SNOWFLAKE_JWT"
export SNOWFLAKE_PRIVATE_KEY_PATH="$HOME/.snowflake/keys/svc_deploy_rsa_key.p8"

echo "Variáveis Snowflake carregadas no ambiente."
```

## Passo 6 — Liberar execução de scripts PowerShell (Windows)

Por padrão, o Windows bloqueia execução de `.ps1`. Liberar para o usuário atual:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Confirmar com `S` quando pedir.

`RemoteSigned` permite scripts locais; bloqueia scripts baixados da internet
sem assinatura digital. É o nível padrão para máquina de desenvolvedor.

## Validação final

Em uma nova sessão de terminal:

```powershell
# PowerShell
. .\scripts\load-env.ps1
$env:SNOWFLAKE_ACCOUNT
```

```bash
# Bash
source scripts/load-env.sh
echo $SNOWFLAKE_ACCOUNT
```

Deve imprimir o account identifier configurado.

Com isso, todas as ferramentas locais (`snow`, `schemachange`) estão prontas
para se conectar ao Snowflake.

## Troubleshooting

**Erro: `Connection default is not configured`**

Causa: `default_connection_name` não está sendo lido. Geralmente porque o
`config.toml` tem o campo posicionado dentro de uma seção `[connections.*]`
em vez de no topo do arquivo.

Fix: garantir que `default_connection_name = "..."` é a primeira linha não-comentada
do arquivo, antes de qualquer `[seção]`.

**Erro: `UserWarning: Unauthorized users have access to configuration file`**

Causa: permissões do `config.toml` muito permissivas.

Fix: rodar os comandos `icacls` (Windows) ou `chmod 0600` (Linux/macOS) do Passo 3.

**Erro: `JWT token is invalid` no `snow connection test`**

Causa: chave pública registrada no Snowflake não corresponde à chave privada
no `private_key_file`, ou foi registrada com quebras de linha.

Fix: refazer Passo 4 do Runbook 01 — extrair conteúdo da chave pública sem
quebras de linha e fazer `ALTER USER SVC_DEPLOY SET RSA_PUBLIC_KEY = '...'`.

**Erro: `O arquivo .ps1 não pode ser carregado porque a execução de scripts foi desabilitada`**

Causa: ExecutionPolicy do PowerShell em modo `Restricted`.

Fix: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`.

**Erro: `Path ...svc_deploy_rsa_key.p8 does not exist`**

Causa: o `private_key_file` no `config.toml` aponta para caminho que não existe,
ou o nome do arquivo está diferente do gerado.

Fix: confirmar com `dir $env:USERPROFILE\.snowflake\keys\` (PowerShell) ou
`ls ~/.snowflake/keys/` (bash) o nome real do arquivo, e ajustar no `config.toml`.

## Próximos passos

- [Runbook 03 — Setup do projeto GCP](03-configure-gcp-project.md)
- [Runbook 05 — Deploy de migrations](05-deploy-migrations.md)