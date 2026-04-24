FROM postgres:16

# Define timezone
ENV TZ=America/Sao_Paulo

# Instala timezone e configurações
RUN apt-get update && \
    apt-get install -y tzdata && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copia os scripts de inicialização
COPY init-scripts/ /docker-entrypoint-initdb.d/

# Define permissões corretas para os scripts
RUN chmod -R 755 /docker-entrypoint-initdb.d/

# Expõe a porta do PostgreSQL
EXPOSE 5432

# Cria um volume para persistência dos dados
VOLUME ["/var/lib/postgresql/data"]

# Define usuário postgres como padrão
USER postgres