#!/bin/bash

# Script de inicialização SSL para n8n Stack
# Execute APÓS fazer deploy no Coolify/VPS

set -e

echo "🔐 Inicializando SSL com Let's Encrypt..."

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Execute como root: sudo ./init-ssl.sh${NC}"
    exit 1
fi

# Configuração
DOMAINS=(
    "n8n.oficinadamultape.com.br"
    "n8n-webhook.oficinadamultape.com.br"
    "grafana.oficinadamultape.com.br"
    "rabbitmq.oficinadamultape.com.br"
    "prometheus.oficinadamultape.com.br"
)
EMAIL="dalexperia@gmail.com"
STAGING=0  # Mude para 1 para testar

echo -e "${YELLOW}📋 Domínios a certificar:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo "   - $domain"
done
echo ""

# Verificar DNS
echo -e "${YELLOW}🔍 Verificando DNS...${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -n "   Verificando $domain... "
    if host "$domain" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ (DNS não configurado)${NC}"
    fi
done
echo ""

read -p "Continuar com a geração de certificados? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Gerar certificados
for domain in "${DOMAINS[@]}"; do
    echo -e "${GREEN}📜 Gerando certificado para: $domain${NC}"
    
    # Construir comando certbot
    CMD="docker-compose run --rm certbot certonly --webroot"
    CMD="$CMD --webroot-path=/var/www/certbot"
    CMD="$CMD --email $EMAIL"
    CMD="$CMD --agree-tos"
    CMD="$CMD --no-eff-email"
    
    if [ $STAGING -eq 1 ]; then
        CMD="$CMD --staging"
    fi
    
    CMD="$CMD -d $domain"
    
    # Executar
    eval $CMD || {
        echo -e "${RED}⚠️  Falha ao gerar certificado para $domain${NC}"
        continue
    }
    
    echo -e "${GREEN}✓ Certificado gerado para $domain${NC}"
done

# Recarregar Nginx
echo -e "${YELLOW}🔄 Recarregando Nginx...${NC}"
docker-compose exec nginx nginx -s reload

echo ""
echo -e "${GREEN}✅ SSL configurado com sucesso!${NC}"
echo ""
echo -e "${YELLOW}🌐 Acesse seus serviços:${NC}"
for domain in "${DOMAINS[@]}"; do
    echo "   https://$domain"
done
echo ""
echo -e "${YELLOW}📝 Renovação automática configurada!${NC}"
echo "   Certificados serão renovados automaticamente a cada 12h"