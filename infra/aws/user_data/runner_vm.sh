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
  gnupg \
  lsb-release \
  postgresql-client \
  ca-certificates \
  libicu-dev

# ── 2. Azure CLI ───────────────────────────────────────────────────────────────
if ! command -v az &>/dev/null; then
  log "INFO" "Installing Azure CLI..."
  curl -sL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
  echo "deb [arch=arm64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/azure-cli.list
  apt-get update -y
  apt-get install -y azure-cli
  log "INFO" "Azure CLI $(az version --query '\"azure-cli\"' -o tsv) installed."
fi

# ── 4. GitHub runner user ──────────────────────────────────────────────────────
if ! id "$RUNNER_USER" &>/dev/null; then
  log "INFO" "Creating $RUNNER_USER user..."
  useradd -m -s /bin/bash "$RUNNER_USER"
fi

# ── 5. Download GitHub Actions runner ─────────────────────────────────────────
if [[ ! -d "$RUNNER_DIR" ]]; then
  log "INFO" "Downloading GitHub Actions runner v$RUNNER_VERSION..."
  sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-arm64-$RUNNER_VERSION.tar.gz" \
    -o /tmp/actions-runner.tar.gz
  sudo -u "$RUNNER_USER" tar -xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
  rm /tmp/actions-runner.tar.gz
fi

# ── 6. Configure runner ────────────────────────────────────────────────────────
log "INFO" "Configuring runner for $GH_REPO..."
sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" \
  --url "https://github.com/$GH_REPO" \
  --token "$GH_RUNNER_TOKEN" \
  --labels "self-hosted,demo" \
  --name "demo-runner-$(hostname)" \
  --unattended \
  --replace

# ── 7. Install as systemd service ─────────────────────────────────────────────
log "INFO" "Installing runner as systemd service..."
cd "$RUNNER_DIR"
"$RUNNER_DIR/svc.sh" install "$RUNNER_USER"
"$RUNNER_DIR/svc.sh" start

log "INFO" "Runner VM bootstrap complete."
log "INFO" "  Runner registered to: https://github.com/$GH_REPO"
log "INFO" "  Labels: self-hosted, demo"
