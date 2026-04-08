#!/usr/bin/env bash
set -euo pipefail

# ── Injected by Terraform templatefile ────────────────────────────────────────
GH_RUNNER_TOKEN="${gh_runner_token}"
GH_REPO="${gh_repo}"

RUNNER_VERSION="2.317.0"
RUNNER_DIR="/home/github-runner/actions-runner"
RUNNER_USER="github-runner"
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
  curl \
  jq \
  git \
  postgresql-client \
  ca-certificates \
  libicu-dev

# ── 2. GitHub runner user ──────────────────────────────────────────────────────
if ! id "$RUNNER_USER" &>/dev/null; then
  log "INFO" "Creating $RUNNER_USER user..."
  useradd -m -s /bin/bash "$RUNNER_USER"
fi

# ── 3. Download GitHub Actions runner ─────────────────────────────────────────
if [[ ! -d "$RUNNER_DIR" ]]; then
  log "INFO" "Downloading GitHub Actions runner v$RUNNER_VERSION..."
  sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-x64-$RUNNER_VERSION.tar.gz" \
    -o /tmp/actions-runner.tar.gz
  sudo -u "$RUNNER_USER" tar -xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
  rm /tmp/actions-runner.tar.gz
fi

# ── 4. Configure runner ────────────────────────────────────────────────────────
log "INFO" "Configuring runner for $GH_REPO..."
sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" \
  --url "https://github.com/$GH_REPO" \
  --token "$GH_RUNNER_TOKEN" \
  --labels "self-hosted,demo" \
  --name "demo-runner-$(hostname)" \
  --unattended \
  --replace

# ── 5. Install as systemd service ─────────────────────────────────────────────
log "INFO" "Installing runner as systemd service..."
"$RUNNER_DIR/svc.sh" install "$RUNNER_USER"
"$RUNNER_DIR/svc.sh" start

log "INFO" "Runner VM bootstrap complete."
log "INFO" "  Runner registered to: https://github.com/$GH_REPO"
log "INFO" "  Labels: self-hosted, demo"
