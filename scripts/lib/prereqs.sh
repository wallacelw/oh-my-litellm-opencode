#!/usr/bin/env bash
# prereqs.sh — Shared prerequisite installation helpers
#
# Source from any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/prereqs.sh"
#
# Mode is controlled by $PREREQ_MODE:
#   auto   — install without prompting (agent/CI mode)
#   prompt — ask y/n before installing (interactive, default when tty)
#
# All functions are idempotent: safe to call multiple times.

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Run with sudo if not root, directly if root
_prereq_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Run apt-get update once per process
declare -g _PREREQ_APT_UPDATED=false
_prereq_apt_update_once() {
  if [ "$_PREREQ_APT_UPDATED" = true ]; then
    return 0
  fi
  _prereq_sudo apt-get update -qq
  _PREREQ_APT_UPDATED=true
}

# Exit 1 with an install hint
_prereq_fail() {
  local name="$1"
  echo "ERROR: Required prerequisite '$name' is not available and could not be installed." >&2
  exit 1
}

# Prompt user y/n (only in prompt mode); returns 0 for yes, 1 for no
_prereq_prompt() {
  local question="$1"
  if [ "${PREREQ_MODE:-auto}" = "auto" ]; then
    return 0
  fi
  # Non-interactive shell → auto-install
  if [ ! -t 0 ]; then
    return 0
  fi
  local answer
  while true; do
    read -rp "$question [y/N] " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]|"") return 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Ensure a command is on PATH; install via apt-get if missing.
#   prereq_ensure_apt <display_name> <command> <apt_package>
prereq_ensure_apt() {
  local display_name="$1"
  local cmd="$2"
  local pkg="$3"

  if command -v "$cmd" &>/dev/null; then
    return 0
  fi

  echo "→ Installing $display_name ($pkg)..."
  if ! _prereq_prompt "  Install $display_name?"; then
    _prereq_fail "$display_name"
  fi

  _prereq_apt_update_once
  _prereq_sudo apt-get install -y -qq "$pkg"
  export _PREREQ_APT_UPDATED=true

  if ! command -v "$cmd" &>/dev/null; then
    _prereq_fail "$display_name"
  fi
  echo "  ✓ $display_name installed"
}

# Ensure bun is available (special: needs PATH sourcing after install)
prereq_ensure_bun() {
  if command -v bun &>/dev/null; then
    return 0
  fi

  echo "→ Installing bun..."
  if ! _prereq_prompt "  Install bun?"; then
    _prereq_fail "bun"
  fi

  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"

  if ! command -v bun &>/dev/null; then
    _prereq_fail "bun"
  fi
  echo "  ✓ bun installed"
}

# Ensure node + npm are available
prereq_ensure_npm() {
  if command -v npm &>/dev/null && command -v node &>/dev/null; then
    return 0
  fi

  echo "→ Installing Node.js + npm..."
  if ! _prereq_prompt "  Install Node.js + npm?"; then
    _prereq_fail "npm/node"
  fi

  _prereq_apt_update_once
  _prereq_sudo apt-get install -y -qq nodejs npm

  if ! command -v npm &>/dev/null; then
    _prereq_fail "npm"
  fi
  echo "  ✓ Node.js + npm installed"
}

# Ensure docker + compose plugin + daemon are running
prereq_ensure_docker() {
  # Install docker engine if missing
  if ! command -v docker &>/dev/null; then
    echo "→ Installing Docker Engine..."
    if ! _prereq_prompt "  Install Docker?"; then
      _prereq_fail "docker"
    fi
    curl -fsSL https://get.docker.com | _prereq_sudo sh
  fi

  # Ensure compose plugin
  if ! docker compose version &>/dev/null; then
    echo "→ Installing Docker Compose plugin..."
    _prereq_apt_update_once
    _prereq_sudo apt-get install -y -qq docker-compose-v2
  fi

  # Start daemon if not running
  if ! docker info &>/dev/null 2>&1; then
    echo "→ Starting Docker daemon..."
    _prereq_sudo systemctl start docker
    sleep 3
  fi

  # Final check
  if ! docker info &>/dev/null 2>&1; then
    _prereq_fail "docker daemon"
  fi
  echo "  ✓ Docker ready"
}
