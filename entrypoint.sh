#!/bin/bash
set -e

echo "Starting True Docker-in-Docker wrapper for Vibe Kanban Cloud..."

# Handle PUID and PGID for the /data directory to ensure correct permissions
PUID=${PUID:-99}
PGID=${PGID:-100}
echo "Setting permissions for /data to PUID: $PUID and PGID: $PGID"
chown -R "$PUID":"$PGID" /data

# Start the docker daemon in the background
dockerd-entrypoint.sh &
DOCKER_PID=$!

echo "Waiting for internal Docker daemon to initialize..."
until docker info >/dev/null 2>&1; do
    sleep 1
done
echo "Internal Docker daemon is ready."

ENV_FILE="/data/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "First run detected: Generating secure secrets in /data/.env..."
    touch "$ENV_FILE"
    echo "DB_PASSWORD=$(openssl rand -base64 48 | tr -d '\n')" >> "$ENV_FILE"
    echo "VIBEKANBAN_REMOTE_JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')" >> "$ENV_FILE"
    echo "ELECTRIC_ROLE_PASSWORD=$(openssl rand -base64 48 | tr -d '\n')" >> "$ENV_FILE"
    chown "$PUID":"$PGID" "$ENV_FILE"
else
    echo "Existing configuration found in /data/.env. Loading secrets..."
fi

# Load the generated secrets into the current shell so docker-compose can use them
source "$ENV_FILE"

# Prepare Caddy / Proxy configuration
export DOMAIN="${DOMAIN:-localhost}"
export USE_EXTERNAL_PROXY="${USE_EXTERNAL_PROXY:-false}"
export TLS_EMAIL="${TLS_EMAIL:-}"

if [ "$USE_EXTERNAL_PROXY" = "true" ]; then
    echo "USE_EXTERNAL_PROXY is true. Disabling internal Caddy..."
    export CADDY_PROFILE="--profile none"
else
    echo "USE_EXTERNAL_PROXY is false. Enabling internal Caddy for SSL..."
    export CADDY_PROFILE="--profile internal_proxy"
    
    # Determine TLS directive
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$DOMAIN" == *"local"* ]]; then
        echo "Local domain detected. Caddy will use internal CA."
        TLS_DIRECTIVE="tls internal"
        # Auto-export root cert for local TLS in background
        (
            echo "Waiting for Caddy to generate internal Root CA..."
            until [ -f /data/caddy_data/caddy/pki/authorities/local/root.crt ]; do
                sleep 5
            done
            cp /data/caddy_data/caddy/pki/authorities/local/root.crt /data/TRUST_ME_FOR_LOCAL_SSL.crt
            chown "$PUID":"$PGID" /data/TRUST_ME_FOR_LOCAL_SSL.crt
            echo "Successfully exported Local SSL Root Certificate to /data/TRUST_ME_FOR_LOCAL_SSL.crt"
        ) &
    else
        if [ -n "$TLS_EMAIL" ]; then
            echo "Public domain with TLS_EMAIL provided."
            TLS_DIRECTIVE="tls $TLS_EMAIL"
        else
            echo "Public domain without TLS_EMAIL. Caddy will use default Let's Encrypt flow."
            TLS_DIRECTIVE=""
        fi
    fi

    # Generate Caddyfile
    echo "{$DOMAIN} {" > /app/Caddyfile
    if [ -n "$TLS_DIRECTIVE" ]; then
        echo "    $TLS_DIRECTIVE" >> /app/Caddyfile
    fi
    echo "    reverse_proxy remote-server:8081" >> /app/Caddyfile
    echo "}" >> /app/Caddyfile
    echo "Caddyfile generated:"
    cat /app/Caddyfile
fi

echo "Starting Vibe Kanban inner stack..."
cd /app

# Ensure we pass the correct variables to compose
export DB_PASSWORD
export VIBEKANBAN_REMOTE_JWT_SECRET
export ELECTRIC_ROLE_PASSWORD
export SELF_HOST_LOCAL_AUTH_EMAIL="${SELF_HOST_LOCAL_AUTH_EMAIL:-}"
export SELF_HOST_LOCAL_AUTH_PASSWORD="${SELF_HOST_LOCAL_AUTH_PASSWORD:-}"
export GITHUB_OAUTH_CLIENT_ID="${GITHUB_OAUTH_CLIENT_ID:-}"
export GITHUB_OAUTH_CLIENT_SECRET="${GITHUB_OAUTH_CLIENT_SECRET:-}"
export GOOGLE_OAUTH_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"
export GOOGLE_OAUTH_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET:-}"

docker compose $CADDY_PROFILE up -d

echo "Stack started successfully. Tailing logs..."
docker compose $CADDY_PROFILE logs -f

# If compose exits, stop the docker daemon
kill $DOCKER_PID
wait $DOCKER_PID
