#!/bin/bash

# Script para configurar SSL com Let's Encrypt
# Execute este script DEPOIS que o Nginx estiver rodando em HTTP

set -e  # Para em caso de erro

echo "🔒 Configurando SSL com Let's Encrypt..."

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Execute como root: sudo ./setup-ssl-fixed.sh${NC}"
    exit 1
fi

# Verificar se o Docker está instalado
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker não encontrado. Instale o Docker primeiro.${NC}"
    exit 1
fi

# Variáveis
DOMAINS=(
    "n8n.oficinadamultape.com.br"
    "n8n-webhook.oficinadamultape.com.br"
    "grafana.oficinadamultape.com.br"
    "rabbitmq.oficinadamultape.com.br"
    "prometheus.oficinadamultape.com.br"
)
EMAIL="dalexperia@gmail.com"

echo -e "${YELLOW}📋 Domínios a serem certificados:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo "   - $domain"
done
echo ""

# Parar o Nginx temporariamente
echo -e "${YELLOW}⏸️  Parando Nginx...${NC}"
docker-compose stop nginx || docker compose stop nginx

# Aguardar
sleep 2

# Instalar Certbot se necessário
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}📦 Instalando Certbot...${NC}"
    apt update
    apt install -y certbot
fi

# Criar diretório para certificados
echo -e "${YELLOW}📁 Criando diretórios...${NC}"
mkdir -p ./nginx/ssl/live
mkdir -p ./nginx/ssl/archive

# Gerar certificados para cada domínio
for domain in "${DOMAINS[@]}"; do
    echo -e "${GREEN}📜 Gerando certificado para: $domain${NC}"

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --preferred-challenges http \
        -d "$domain" || {
            echo -e "${RED}⚠️  Falha ao gerar certificado para $domain${NC}"
            echo -e "${YELLOW}   Continuando com próximo domínio...${NC}"
            continue
        }

    # Copiar certificados
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${GREEN}   ✅ Copiando certificados de $domain${NC}"
        cp -rL "/etc/letsencrypt/live/$domain" "./nginx/ssl/live/"
        chmod -R 755 "./nginx/ssl/live/$domain"
    fi
done

# Atualizar configuração do Nginx para usar SSL
echo -e "${YELLOW}⚙️  Atualizando configuração do Nginx...${NC}"

cat > ./nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # n8n Main - HTTP redirect
    server {
        listen 80;
        server_name n8n.oficinadamultape.com.br;
        return 301 https://$server_name$request_uri;
    }

    # n8n Main - HTTPS
    server {
        listen 443 ssl http2;
        server_name n8n.oficinadamultape.com.br;

        ssl_certificate /etc/nginx/ssl/live/n8n.oficinadamultape.com.br/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/live/n8n.oficinadamultape.com.br/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://n8n:5678;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 86400;
        }
    }

    # n8n Webhook - HTTP redirect
    server {
        listen 80;
        server_name n8n-webhook.oficinadamultape.com.br;
        return 301 https://$server_name$request_uri;
    }

    # n8n Webhook - HTTPS
    server {
        listen 443 ssl http2;
        server_name n8n-webhook.oficinadamultape.com.br;

        ssl_certificate /etc/nginx/ssl/live/n8n-webhook.oficinadamultape.com.br/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/live/n8n-webhook.oficinadamultape.com.br/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://n8n:5678;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
        }
    }

    # Grafana - HTTP redirect
    server {
        listen 80;
        server_name grafana.oficinadamultape.com.br;
        return 301 https://$server_name$request_uri;
    }

    # Grafana - HTTPS
    server {
        listen 443 ssl http2;
        server_name grafana.oficinadamultape.com.br;

        ssl_certificate /etc/nginx/ssl/live/grafana.oficinadamultape.com.br/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/live/grafana.oficinadamultape.com.br/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://grafana:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
        }
    }
}
EOF

# Reiniciar Nginx
echo -e "${GREEN}🚀 Iniciando Nginx com SSL...${NC}"
docker-compose up -d nginx || docker compose up -d nginx

# Aguardar Nginx iniciar
sleep 3

# Verificar se está rodando
if docker ps | grep -q nginx; then
    echo -e "${GREEN}✅ Nginx iniciado com sucesso!${NC}"
else
    echo -e "${RED}❌ Erro ao iniciar Nginx. Verificando logs...${NC}"
    docker logs nginx
    exit 1
fi

echo ""
echo -e "${GREEN}✅ SSL configurado com sucesso!${NC}"
echo ""
echo -e "${YELLOW}📝 Informações importantes:${NC}"
echo "   - Certificados expiram em 90 dias"
echo "   - Configure renovação automática com: certbot renew"
echo ""
echo -e "${GREEN}🌐 Acesse seus serviços:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo "   - https://$domain"
done
echo ""

# Criar cron job para renovação automática
echo -e "${YELLOW}⏰ Configurando renovação automática...${NC}"
cat > /etc/cron.d/certbot-renew << 'CRONEOF'
# Renovar certificados às 3:00 AM todo dia
0 3 * * * root certbot renew --quiet --post-hook "docker-compose -f /caminho/completo/docker-compose.yml restart nginx"
CRONEOF

echo -e "${GREEN}✅ Setup completo!${NC}"