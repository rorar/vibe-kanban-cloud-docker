FROM docker:24-dind

RUN apk add --no-cache bash openssl curl jq docker-cli-compose

WORKDIR /app

COPY entrypoint.sh /app/
COPY docker-compose.prod.yml /app/

RUN chmod +x /app/entrypoint.sh

VOLUME /data

ENTRYPOINT ["/app/entrypoint.sh"]