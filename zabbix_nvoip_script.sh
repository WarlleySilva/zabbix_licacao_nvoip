#!/bin/bash

# Função para registrar logs
LOG_DIR="/var/log/zabbix/nvoip"
LOG_FILE="$LOG_DIR/ligacoes.log"

log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Cria o diretório de log, se não existir
mkdir -p "$LOG_DIR"

# Verifica se os argumentos foram passados
if [ "$#" -ne 2 ]; then
    log_message "Erro: Número incorreto de parâmetros."
    exit 1
fi

# Parâmetros passados pelo Zabbix
NUMERO_DESTINO=$1
MENSAGEM=$2

# Remove aspas extras da mensagem
MENSAGEM=$(echo "$MENSAGEM" | sed 's/^"//;s/"$//')

# Remove caracteres especiais e converte para texto simples
NUMERO_DESTINO=$(echo "$NUMERO_DESTINO" | tr -cd '[:digit:]')
MENSAGEM=$(echo "$MENSAGEM" | tr -d '\n' | tr -cd '[:alnum:][:space:][:punct:]')

# Limita o tamanho da mensagem para 160 caracteres
if [ ${#MENSAGEM} -gt 160 ]; then
    MENSAGEM=$(echo "$MENSAGEM" | cut -c 1-160)
    log_message "Mensagem truncada para 160 caracteres: $MENSAGEM"
fi

# Define o PATH para garantir que os comandos estejam disponíveis
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Log inicial
log_message "Iniciando script com os seguintes parâmetros:"
log_message "Destinatário: $NUMERO_DESTINO"
log_message "Mensagem: $MENSAGEM"

# Credenciais para obter o access_token
USERNAME="YOUR-NUMBERSIP"
PASSWORD="YOUR-USER-TOKEN"

# URL para obter o access_token
AUTH_URL="https://api.nvoip.com.br/v2/oauth/token"

# Obtém o access_token
log_message "Obtendo access_token..."
RESPONSE=$(curl -s -X POST "$AUTH_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Authorization: Basic TnZvaXBBcGlWMjpUblp2YVhCQmNHbFdNakl3TWpFPQ==" \
    -d "username=$USERNAME&password=$PASSWORD&grant_type=password")

# Extrai o access_token da resposta
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

# Verifica se o access_token foi obtido com sucesso
if [ "$ACCESS_TOKEN" == "null" ]; then
    log_message "Erro ao obter o access_token. Resposta da API: $RESPONSE"
    exit 1
fi

log_message "Access_token obtido com sucesso."

# URL para enviar o torpedo de voz
TORPEDO_URL="https://api.nvoip.com.br/v2/torpedo/voice"

# Monta o JSON para a requisição
JSON_BODY=$(cat <<EOF
{
    "caller": "$USERNAME",
    "called": "$NUMERO_DESTINO",
    "audios": [
        {
            "audio": "$(echo "$MENSAGEM" | tr -d '\n')",
            "positionAudio": 1
        }
    ],
    "dtmfs": []
}
EOF
)

# Valida o JSON usando jq
if ! echo "$JSON_BODY" | jq empty; then
    log_message "Erro: JSON inválido. Corpo da requisição: $JSON_BODY"
    exit 1
fi

log_message "JSON enviado para a API: $JSON_BODY"

# Envia o torpedo de voz
log_message "Enviando torpedo de voz para o número $NUMERO_DESTINO com a mensagem: $MENSAGEM"
TORPEDO_RESPONSE=$(curl -s -X POST "$TORPEDO_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY")

log_message "Resposta completa da API: $TORPEDO_RESPONSE"

# Verifica a resposta do envio do torpedo
if echo "$TORPEDO_RESPONSE" | grep -q '"status":"Completada"'; then
    log_message "Torpedo de voz enviado com sucesso! Resposta da API: $TORPEDO_RESPONSE"
    exit 0
else
    log_message "Erro ao enviar o torpedo de voz. Resposta da API: $TORPEDO_RESPONSE"
    exit 1
fi