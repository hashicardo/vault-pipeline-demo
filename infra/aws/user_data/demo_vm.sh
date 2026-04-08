#!/usr/bin/env bash
set -euo pipefail

# ── Injected by Terraform templatefile ────────────────────────────────────────
POSTGRES_PASSWORD="${postgres_password}"
DOMAIN_NAME="${domain_name}"
CLOUDFLARE_API_TOKEN="${cloudflare_api_token}"
GH_REPO="${gh_repo}"

DEMO_DIR="/opt/demo"
CADDY_BIN="/usr/local/bin/caddy"
LOGFILE="/var/log/bootstrap.log"

export DEBIAN_FRONTEND=noninteractive

# ── Logging ───────────────────────────────────────────────────────────────────

function log {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local log_entry="$timestamp [$level] - $message"
  echo "$log_entry" | sudo tee -a "$LOGFILE"
}

function on_error {
  local exit_code=$?
  local line_no=$1
  log "ERROR" "Script failed with exit code $exit_code at line $line_no"
}

trap 'on_error $LINENO' ERR

# ── 1. System packages ─────────────────────────────────────────────────────────
log "INFO" "Installing system packages..."
apt-get update -y
apt-get install -y \
  docker.io \
  docker-compose \
  curl \
  git \
  jq \
  ca-certificates

systemctl enable docker
systemctl start docker

# ── 2. Caddy with Cloudflare DNS module ───────────────────────────────────────
if [[ ! -x "$CADDY_BIN" ]]; then
  log "INFO" "Downloading Caddy with Cloudflare DNS module..."
  curl -fsSL \
    "https://caddyserver.com/api/download?os=linux&arch=arm64&p=github.com%2Fcaddy-dns%2Fcloudflare" \
    -o "$CADDY_BIN"
  chmod +x "$CADDY_BIN"
  setcap cap_net_bind_service=+ep "$CADDY_BIN" || true
fi

# ── 3. Clone demo repo ─────────────────────────────────────────────────────────
if [[ ! -d "$DEMO_DIR/.git" ]]; then
  log "INFO" "Cloning $GH_REPO..."
  git clone "https://github.com/$GH_REPO.git" "$DEMO_DIR"
else
  log "INFO" "Repo already cloned, pulling latest..."
  git -C "$DEMO_DIR" pull --ff-only || true
fi

# ── 4. Docker Compose file ────────────────────────────────────────────────────
log "INFO" "Writing docker-compose.yml..."
cat > "$DEMO_DIR/docker-compose.yml" <<'COMPOSE'
version: '3.8'

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: demo_app
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d demo_app"]
      interval: 5s
      timeout: 5s
      retries: 10

  web-server:
    build: /opt/demo/web/
    environment:
      DB_HOST: postgres
      DB_NAME: demo_app
      DB_USER: postgres
      DB_PASS: $${POSTGRES_PASSWORD}
    ports:
      - "8080:8080"
    restart: always
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  pgdata:
COMPOSE

# ── 5. Bootstrap PostgreSQL schema ─────────────────────────────────────────────
log "INFO" "Starting containers..."
cd "$DEMO_DIR"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker-compose up -d postgres

log "INFO" "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  if docker-compose exec -T postgres pg_isready -U postgres -d demo_app &>/dev/null; then
    break
  fi
  sleep 2
done

log "INFO" "Applying schema..."
docker-compose exec -T postgres psql -U postgres -d demo_app <<'SQL'
CREATE TABLE IF NOT EXISTS secret_log (
  id          SERIAL PRIMARY KEY,
  username    TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ttl_seconds INTEGER NOT NULL DEFAULT 300
);
SQL

log "INFO" "Starting web server..."
POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker-compose up -d web-server

# ── 6. Caddyfile ───────────────────────────────────────────────────────────────
log "INFO" "Writing Caddyfile..."
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<CADDYFILE
$DOMAIN_NAME {
    reverse_proxy localhost:8080

    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
}
CADDYFILE

# ── 7. Caddy systemd service ───────────────────────────────────────────────────
log "INFO" "Configuring Caddy systemd service..."
cat > /etc/systemd/system/caddy.service <<'SYSTEMD'
[Unit]
Description=Caddy reverse proxy (Cloudflare DNS TLS)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=CLOUDFLARE_API_TOKEN=__CF_TOKEN__
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMD

# Inject real Cloudflare token into the service env
sed -i "s|__CF_TOKEN__|$CLOUDFLARE_API_TOKEN|g" /etc/systemd/system/caddy.service

systemctl daemon-reload
systemctl enable caddy
systemctl start caddy

log "INFO" "Demo VM bootstrap complete."
log "INFO" "  Web UI:     https://$DOMAIN_NAME"
log "INFO" "  PostgreSQL: $DOMAIN_NAME:5432 (restricted to runner-vm-sg)"
