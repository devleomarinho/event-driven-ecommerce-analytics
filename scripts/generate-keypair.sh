#!/usr/bin/env bash
# scripts/generate-keypair.sh
# Gera par de chaves RSA 2048 (PKCS#8, sem passphrase) para Snowflake key-pair auth.
# Compatível com Git Bash (Windows), macOS e Linux — depende apenas de OpenSSL.

set -euo pipefail

# ---------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------
KEY_DIR="${HOME}/.snowflake/keys"
KEY_NAME="svc_deploy"
PRIVATE_KEY="${KEY_DIR}/${KEY_NAME}.p8"
PUBLIC_KEY="${KEY_DIR}/${KEY_NAME}.pub"

# ---------------------------------------------------------------------
# Pré-validações
# ---------------------------------------------------------------------
if ! command -v openssl &> /dev/null; then
    echo "ERRO: openssl não encontrado no PATH."
    echo "  - Windows: use Git Bash (traz openssl embutido)"
    echo "  - macOS:   já vem pré-instalado"
    echo "  - Linux:   instale via apt/yum"
    exit 1
fi

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}" 2>/dev/null || true  # chmod silencioso no Windows

# Guarda: evita sobrescrever chave já registrada no Snowflake
if [[ -f "${PRIVATE_KEY}" ]]; then
    echo "ERRO: chave já existe em ${PRIVATE_KEY}"
    echo "Se precisa rotacionar, faça backup e remova manualmente antes."
    exit 1
fi

# ---------------------------------------------------------------------
# Geração do par de chaves
# Por quê esses flags:
#   - genrsa 2048   : RSA 2048-bit (mínimo exigido pela Snowflake)
#   - pkcs8 -topk8  : formato PKCS#8 (esperado pelo Snowflake Connector)
#   - -nocrypt      : sem passphrase (trade-off documentado no README)
# ---------------------------------------------------------------------
echo "Gerando chave privada RSA 2048 (PKCS#8, não-criptografada)..."
openssl genrsa 2048 \
    | openssl pkcs8 -topk8 -inform PEM -out "${PRIVATE_KEY}" -nocrypt

echo "Derivando chave pública..."
openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"

# Permissões (no-op no Windows, mas importante em Unix)
chmod 600 "${PRIVATE_KEY}" 2>/dev/null || true
chmod 644 "${PUBLIC_KEY}"  2>/dev/null || true

# ---------------------------------------------------------------------
# Sumário + próximos passos
# ---------------------------------------------------------------------
echo ""
echo "✓ Chaves geradas:"
echo "    Privada: ${PRIVATE_KEY}"
echo "    Pública: ${PUBLIC_KEY}"
echo ""
echo "Próximos passos:"
echo ""
echo "  1. Extraia o conteúdo da chave pública (sem as linhas BEGIN/END):"
echo ""
echo "     grep -v 'PUBLIC KEY' '${PUBLIC_KEY}' | tr -d '\\n'"
echo ""
echo "     Copie o output — é um blob base64 contínuo."
echo ""
echo "  2. Registre no Snowflake via Snowsight (como ACCOUNTADMIN):"
echo ""
echo "     ALTER USER SVC_DEPLOY SET RSA_PUBLIC_KEY='<cole_aqui>';"
echo ""
echo "  3. Valide que ficou correto:"
echo ""
echo "     DESC USER SVC_DEPLOY;   -- procure por RSA_PUBLIC_KEY_FP"
echo ""
echo "  4. Teste a conexão:"
echo ""
echo "     snow connection add --connection-name portfolio-deploy \\"
echo "         --account <seu_account> --user SVC_DEPLOY \\"
echo "         --private-key-file '${PRIVATE_KEY}'"
echo "     snow connection test --connection portfolio-deploy"