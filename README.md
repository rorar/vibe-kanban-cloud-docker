# Vibe Kanban Cloud - True DinD Wrapper

This project provides a pristine, "one-click" deployable Docker image for [Vibe Kanban Cloud](https://github.com/BloopAI/vibe-kanban), specifically optimized for UnRAID and other container management systems.

> **Note**: This repository builds the **Cloud Server** (multi-user, auth-enabled) version of Vibe Kanban. If you are looking for a single-user local development environment, refer to the official documentation.

## 🏗️ Architecture: True Docker-in-Docker (DinD)

Vibe Kanban Cloud relies on a complex stack of interconnected services (`remote-server`, `postgres`, `electricsql`, and optionally `caddy`). 

To prevent cluttering your UnRAID WebUI (or Portainer interface) with multiple unmanaged "sibling" containers, this project utilizes a **True DinD** approach based on `docker:dind`. 

**How it works:**
1. You run exactly **one** container (`ghcr.io/rorar/vibe-kanban-cloud`).
2. This wrapper container spins up its own fully isolated, internal Docker daemon.
3. An `entrypoint.sh` script automatically provisions secure secrets (`DB_PASSWORD`, `JWT_SECRET`, etc.) to a persistent `/data/.env` file.
4. The script then orchestrates the internal `docker-compose` stack entirely within the wrapper.

**Requirement**: The container MUST be run in `Privileged` mode to allow the internal Docker daemon to function.

## 🚀 Features

*   **Pristine UnRAID Integration**: Exposes the entire stack via a single XML template without spamming the Docker tab.
*   **Fully Automated Upstream Sync**: A GitHub Action runs every 6 hours. It checks the official `BloopAI/vibe-kanban` repository for new commits or updated dependency versions (Caddy, Postgres, ElectricSQL). If updates are found, it automatically syncs the versions, builds a fresh DinD image, and publishes it to GHCR.
*   **Zero-Touch Initial Setup**: Automatically generates the required 48-character base64 secrets on the first run.
*   **Flexible Proxy & SSL Routing**: Built-in support for both standalone deployments and setups behind external reverse proxies (like Nginx Proxy Manager or Traefik).

## ⚙️ Configuration & Environment Variables

All configuration is driven by standard environment variables. If you are using UnRAID, these are exposed in the provided XML template.

### Core Variables
| Variable | Description |
| :--- | :--- |
| `DOMAIN` | Your domain name (e.g., `kanban.yourdomain.com`). If you use a local IP or hostname (e.g., `192.168.1.100`), the internal Caddy will automatically generate a local Root CA for internal HTTPS. |
| `USE_EXTERNAL_PROXY` | `true` or `false` (Default: `false`). See the Proxy Modes section below. |
| `PUID` & `PGID` | Defines the permissions for the generated files in the `/data` directory. |

### Authentication (Choose One)
**Option A: Local Bootstrap (Recommended for initial setup)**
| Variable | Description |
| :--- | :--- |
| `SELF_HOST_LOCAL_AUTH_EMAIL` | Email address for the initial local admin user. |
| `SELF_HOST_LOCAL_AUTH_PASSWORD` | Secure password for the initial local admin user. |

**Option B: OAuth**
| Variable | Description |
| :--- | :--- |
| `GITHUB_OAUTH_CLIENT_ID` / `_SECRET` | Credentials for GitHub login. |
| `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` | Credentials for Google login. |

## 🌐 Proxy Modes

Vibe Kanban requires HTTPS. This wrapper provides two ways to handle it:

### 1. Internal Caddy Mode (Default: `USE_EXTERNAL_PROXY=false`)
The wrapper runs its own internal Caddy server to handle SSL termination.
*   **Public Domain**: If `DOMAIN` is a public FQDN, Caddy uses Let's Encrypt (ACME) to fetch a valid certificate. (Optionally provide `TLS_EMAIL`). Map host port `443` -> container port `443` (e.g., `1443:443`).
*   **Local IP/Hostname**: If `DOMAIN` is a local IP, Caddy uses `tls internal`. It generates its own Certificate Authority. The wrapper automatically exports this Root CA to your persistent storage at `/data/TRUST_ME_FOR_LOCAL_SSL.crt`. Install this certificate on your local machine to trust the connection.

### 2. External Proxy Mode (`USE_EXTERNAL_PROXY=true`)
For users who already run Nginx Proxy Manager, Traefik, or an external Caddy instance.
*   The internal Caddy container is completely disabled.
*   The internal `remote-server` exposes plain HTTP on port `8081`.
*   Map host port `8081` -> container port `8081`. Point your external reverse proxy to this port. Your external proxy handles the SSL.

## 💾 Persistence

All stateful data is kept in a single volume mount to ensure backups are simple and data survives container recreation.

Mount a host directory (e.g., `/mnt/user/appdata/vibe-kanban-cloud`) to `/data` inside the container.

**What lives in `/data`?**
*   `.env` (Auto-generated secure secrets)
*   `remote-db-data/` (Postgres database)
*   `electric-data/` (ElectricSQL sync state)
*   `caddy_data/` & `caddy_config/` (SSL certificates and internal proxy state)
*   `TRUST_ME_FOR_LOCAL_SSL.crt` (Exported Root CA if using local domain mode)

## 🐳 Manual Docker Compose Installation (Non-UnRAID)

While optimized for UnRAID, you can run this wrapper anywhere:

```yaml
services:
  vibe-kanban-cloud:
    image: ghcr.io/rorar/vibe-kanban-cloud:latest
    container_name: vibe-kanban-cloud
    privileged: true
    restart: unless-stopped
    ports:
      - "180:80"     # Internal Caddy HTTP
      - "1443:443"   # Internal Caddy HTTPS
      # - "8081:8081" # Uncomment if USE_EXTERNAL_PROXY=true
    volumes:
      - ./vibe-data:/data
    environment:
      - DOMAIN=vibe.local
      - USE_EXTERNAL_PROXY=false
      - SELF_HOST_LOCAL_AUTH_EMAIL=admin@example.com
      - SELF_HOST_LOCAL_AUTH_PASSWORD=changeme
      - PUID=1000
      - PGID=1000
```