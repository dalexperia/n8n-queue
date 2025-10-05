# Usamos uma base Debian padrão com Node.js (necessário para o n8n)
FROM node:20-bookworm

# Instala as dependências do sistema (APENAS Python Dev)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    gcc \
    libcairo2-dev \
    libpango1.0-dev \
    libgdk-pixbuf2.0-dev \
    libffi-dev \
    libnss3 \
    libnspr4 \
    libxss1 \
    libasound2 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libgbm-dev \
    \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Instala o n8n globalmente (Removido 'puppeteer' do npm install)
RUN npm install -g n8n

# Instala as bibliotecas Python essenciais
RUN pip3 install --no-cache-dir --break-system-packages \
    pandas \
    reportlab \
    matplotlib \
    seaborn \
    Pillow

# Cria e configura o restante do ambiente
RUN mkdir -p /usr/local/bin/python-scripts && \
    mkdir -p /tmp/pdfs

COPY scripts/ /usr/local/bin/python-scripts/
RUN chmod +x /usr/local/bin/python-scripts/* 2>/dev/null || true

RUN printf '#!/bin/sh\nexec n8n worker\n' > /worker && \
    printf '#!/bin/sh\nexec n8n webhook\n' > /webhook && \
    chmod +x /worker /webhook

# Variáveis de ambiente
ENV N8N_LOG_LEVEL=info \
    NODE_FUNCTION_ALLOW_EXTERNAL=ajv,ajv-formats
    # NODE_FUNCTION_ALLOW_EXTERNAL=puppeteer foi removido
    # PUPPETEER_SKIP_CHROMIUM_DOWNLOAD foi removido

EXPOSE 5678
CMD ["n8n", "start"]