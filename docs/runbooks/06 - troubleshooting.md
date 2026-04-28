# Runbook 06: Troubleshooting geral

Este runbook agrupa problemas que aparecem em mais de uma fase do projeto e não
são exclusivos de um único setup. Para erros específicos de cada etapa, consultar
a seção "Troubleshooting" do runbook correspondente.

## Encoding e caracteres especiais

### Caracteres estranhos (`â€`, `Ã©`, `Ã£`) no terminal

Causa: arquivo salvo em encoding diferente (geralmente Windows-1252) sendo lido
como UTF-8, ou vice-versa.

Fix:

- No VS Code, verificar o encoding na barra inferior direita. Clicar e escolher
  "Save with Encoding" → "UTF-8".
- Para scripts `.ps1`, garantir UTF-8 (com ou sem BOM funciona).
- Definir como default para o projeto criando `.vscode/settings.json`:

```json
{
    "files.encoding": "utf8",
    "files.eol": "\n"
}
```

### Path do projeto contém caracteres especiais

Causa: caracteres como `#`, `%`, espaços, ou acentos no caminho do diretório
quebram silenciosamente várias ferramentas (Python, Snowflake CLI, gcloud).

Sintomas: arquivos "não encontrados" mesmo existindo, comportamento errático,
truncamento inexplicável.

Fix: mover o projeto para um path com apenas `[a-z0-9-_/]`. Exemplo:

```
Ruim:  D:\#DATAPROJECTS\Portfólio\#projeto-1\meu-repo
Bom:   D:\projects\event-driven-ecommerce
```

Esta é uma classe de bug que evita-se na origem, não se debugga depois.

## PowerShell

### Erro: `O arquivo .ps1 não pode ser carregado porque a execução de scripts foi desabilitada`

Causa: ExecutionPolicy do Windows em modo `Restricted` por default.

Fix:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Confirmar com `S`. Permite scripts locais e bloqueia scripts remotos não
assinados — nível padrão para máquina de desenvolvedor.

### Erro de parser: `Argumento ausente na lista de parâmetros`

Causa: comando multi-linha usando `\` (continuação Bash) em vez de
`` ` `` (backtick, continuação PowerShell).

```powershell
# ERRADO em PowerShell — sintaxe Bash
gcloud storage cp file.json gs://bucket/ \
    --some-flag

# CORRETO em PowerShell
gcloud storage cp file.json gs://bucket/ `
    --some-flag
```

Alternativa robusta para comandos longos: usar splatting:

```powershell
$cmdArgs = @(
    "storage", "cp", "file.json", "gs://bucket/",
    "--some-flag"
)
gcloud @cmdArgs
```

### Variáveis de ambiente "somem" após rodar script

Causa: script foi executado em subshell, não com dot sourcing.

```powershell
# ERRADO — variáveis vivem só dentro do script
.\scripts\load-env.ps1

# CERTO — dot sourcing carrega no shell atual (atenção ao ponto inicial)
. .\scripts\load-env.ps1
```

### Erro: `Vírgula dentro de string em comando externo causa erro de parser`

Causa: PowerShell trata vírgula em alguns contextos como operador de array.

Fix: trocar `--format="table(a, b, c)"` por `--format=json` e processar com
`ConvertFrom-Json`. Mais idiomático e robusto.

## Snowflake

### Erro: `Requested role 'X' is not assigned to the executing user`

Causa: tentativa de usar `USE ROLE` para uma role que o usuário atual não
tem grant.

Fix: verificar grants do usuário:

```sql
SHOW GRANTS TO USER <usuario>;
```

Em migrations, evitar `USE ROLE` para roles não atribuídas ao SVC_DEPLOY —
deixar a role default (`ROLE_DEPLOY`) ativa. Operações que exigem
ACCOUNTADMIN devem ser feitas manualmente por humano com MFA.

### Erro: `Object does not exist, or operation cannot be performed`

Causas possíveis:

1. Falta privilégio `USAGE` no schema/database — confirmar com:

```sql
   SHOW GRANTS TO ROLE <role>;
```

2. O contexto da sessão (database/schema) está errado. Verificar com:

```sql
   SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_ROLE();
```

3. O objeto realmente não existe. Confirmar com `SHOW`:

```sql
   SHOW WAREHOUSES;
   SHOW DATABASES;
   SHOW SCHEMAS IN DATABASE <db>;
```

### Erro: `JWT token is invalid`

Causa: chave pública registrada no Snowflake não corresponde à chave privada
em uso, ou foi registrada com quebras de linha.

Fix:

1. Confirmar que o fingerprint da chave bate. No Snowsight:

```sql
   DESC USER SVC_DEPLOY;
```

   Procurar `RSA_PUBLIC_KEY_FP`. Comparar com fingerprint local:

```bash
   openssl rsa -in ~/.snowflake/keys/svc_deploy_rsa_key.p8 -pubout -outform DER \
       | openssl dgst -sha256 -binary \
       | openssl enc -base64
```

   Os valores devem ser idênticos.

2. Se diferentes, re-extrair a chave pública e refazer `ALTER USER`:

```bash
   grep -v 'PUBLIC KEY' ~/.snowflake/keys/svc_deploy_rsa_key.pub | tr -d '\n'
```

### `USE SCHEMA` não dá erro mesmo sem permissão

Causa: comportamento do Snowflake — `USE SCHEMA` muda contexto da sessão
sem validar privilégio. A validação acontece em operações de leitura/escrita.

Não é bug, é design. Para testar privilégios reais, usar:

```sql
DESCRIBE SCHEMA <db>.<schema>;
SHOW TABLES IN SCHEMA <db>.<schema>;
SELECT * FROM <db>.<schema>.<tabela> LIMIT 1;
```

Esses comandos sim retornam erro se faltar privilégio.

### `SHOW TABLES` retorna 0 rows mesmo com tabelas existentes

Causa: schema com `WITH MANAGED ACCESS` retorna lista vazia para roles sem
USAGE no schema, em vez de erro de privilégio explícito. Comportamento de
segurança intencional ("não revelar estrutura a quem não tem direito").

Para validar privilégio: ver erro acima sobre `USE SCHEMA`.

### Migration falhada bloqueia novos deploys

Causa: schemachange registra a falha na CHANGE_HISTORY com `status='Failed'`.
O hash da migration fica gravado, e qualquer modificação dispara erro de drift.

Fix: ver Runbook 05, seção "Lidando com migrations falhas".

## GCP

### Comandos `gcloud` retornam vazio ou comportamento inesperado

Causa comum: projeto default não está setado.

Fix:

```bash
gcloud config get-value project
# Se vazio ou errado:
gcloud config set project event-driven-snowflake
```

### Erro: `permission denied` mesmo com IAM correto

Causas possíveis:

1. Token do `gcloud` expirou. Re-autenticar:

```bash
   gcloud auth login
```

2. Service account em uso difere do esperado. Verificar:

```bash
   gcloud auth list
```

3. Para operações de bucket, verificar se a conta tem `roles/storage.admin`
   ou equivalente no projeto.

### Auto-ingest do Snowpipe não dispara mesmo com arquivos chegando no bucket

Diagnóstico em ordem:

1. **Notificação está sendo gerada?**

```bash
   gcloud pubsub subscriptions pull <sub-snowflake> --auto-ack --limit=5
```

   Se não retorna nada após upload de arquivo, problema no GCS notification
   (verificar `--object-prefix` e `--event-types`).

2. **Snowflake está consumindo?** Ver logs do pipe:

```sql
   SELECT * FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.PIPE_USAGE_HISTORY(
       DATE_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
       PIPE_NAME => '<DATABASE>.<SCHEMA>.<PIPE_NAME>'
   ));
```

3. **Falta `pubsub.viewer` no projeto?** O service account da Notification
   Integration precisa do role no nível do projeto, além de `subscriber` na
   subscription. Esse detalhe é pouco documentado.

   Fix:
```bash
   gcloud projects add-iam-policy-binding event-driven-snowflake \
       --member="serviceAccount:<SA_NOTIF>" \
       --role="roles/pubsub.viewer"
```

### Erro: `bucket already exists in another project`

Causa: nomes de bucket são globalmente únicos no GCP.

Fix: prefixar o nome (`<seu-prefixo>-raw-events-qa`) e atualizar referências
em V004 e nos scripts.

## schemachange

### Config file não está sendo lido

Sintoma no log:

```
Config file '<path>' not found. Using configuration from CLI arguments,
environment variables, and defaults.
```

Diagnóstico:

```powershell
# Confirma que arquivo existe no path esperado
Test-Path .\infra\snowflake\environments\dev.yml

# Mostra conteúdo
Get-Content .\infra\snowflake\environments\dev.yml
```

Causas comuns:

1. Path passado em `--config-folder` aponta para diretório errado
2. Arquivo salvo com nome diferente (ex: `dev.yaml` em vez de `dev.yml`)
3. Encoding do arquivo corrompido (BOM em local errado, etc.)

### Variáveis Jinja não estão sendo substituídas

Sintoma: SQL executado contém literalmente `{{ database_name }}` em vez do valor.

Causas:

1. O config YAML não tem a seção `vars:` com a variável definida.
2. O arquivo SQL não foi reconhecido como template (extensão errada — deve ser
   `.sql`, não `.SQL` ou `.sql.j2`).

Validar com log do schemachange — a linha `Using variables vars={...}` deve
mostrar todas as variáveis esperadas:

```
Using variables   vars={'env': 'dev', 'database_name': 'ANALYTICS_DEV', ...}
```

Se aparecer `vars={}`, o YAML não foi lido (ver acima).

## Diagnóstico geral

Quando algo não funciona e a causa não é óbvia, executar nesta ordem:

1. **Validação física**: o arquivo/recurso existe onde se espera?

```bash
   ls <caminho>
   gcloud storage ls gs://<bucket>/
   SHOW <objeto> IN <database>;
```

2. **Validação de identidade**: estou autenticado como esperado?

```bash
   snow connection test
   gcloud auth list
   gcloud config get-value project
```

3. **Validação de privilégio**: a role/SA tem o que precisa?

```sql
   SHOW GRANTS TO ROLE <role>;
```

```bash
   gcloud projects get-iam-policy <project> --flatten="bindings[].members" \
       --filter="bindings.members:<SA>"
```

4. **Logs**: o serviço deixou pistas?

   - schemachange: rodar com `-v` ou `--verbose` para mais detalhe
   - gcloud: rodar com `--verbosity=debug`
   - Snowflake: consultar `INFORMATION_SCHEMA.QUERY_HISTORY`

A regra geral: **antes de teorizar sobre o bug, confirmar fisicamente o estado**.
80% dos problemas estranhos são paths/nomes/permissões que se assume estarem
certos sem verificar.

## Fontes de consulta

Se um problema não está coberto aqui e os passos de diagnóstico geral não
resolveram, a documentação oficial costuma ter respostas concretas:

- [Snowflake Documentation](https://docs.snowflake.com/)
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [schemachange GitHub](https://github.com/Snowflake-Labs/schemachange)

Para erros raros, a comunidade do Stack Overflow e o Snowflake Forum
costumam ter casos similares.