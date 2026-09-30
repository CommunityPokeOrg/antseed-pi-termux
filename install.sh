#!/data/data/com.termux/files/usr/bin/bash
# install.sh — set up the AntSeed pi launcher on Termux (Android).
#
# Usage:
#   pkg install git && git clone https://github.com/CommunityPokeOrg/antseed-pi-termux
#   cd antseed-pi-termux && ./install.sh
#
# Or one-shot:
#   curl -fsSL https://raw.githubusercontent.com/CommunityPokeOrg/antseed-pi-termux/main/install.sh | bash

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
ENV_DIR="${ANTSEED_PI_HOME:-$HOME/.antseed-pi}"
PI_ANTSEED_PKG="git:github.com/AntSeed/pi-antseed"

info() { printf '\033[32m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --- sanity: refuse non-Termux environments unless forced -------------------
if [ ! -d "/data/data/com.termux" ] && [ "${ANTSEED_PI_FORCE:-0}" != "1" ]; then
    warn "This doesn't look like Termux. Set ANTSEED_PI_FORCE=1 to install anyway."
    die "Aborting."
fi

# --- 1. Termux packages ------------------------------------------------------
info "Updating packages and installing dependencies (nodejs, git, jq, curl, termux-tools)..."
pkg update -y
pkg install -y nodejs git jq curl coreutils procps

# --- 2. npm globals -----------------------------------------------------------
info "Installing @antseed/cli and @mariozechner/pi-coding-agent from npm..."
npm install -g @antseed/cli @mariozechner/pi-coding-agent

command -v antseed >/dev/null || die "antseed CLI not on PATH after npm install"
command -v pi      >/dev/null || die "pi not on PATH after npm install"
info "antseed: $(antseed --version 2>/dev/null || echo installed)"

# --- 3. launcher on PATH ------------------------------------------------------
info "Installing the antseed-pi launcher into \$PREFIX/bin..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$SCRIPT_DIR/bin/antseed-pi" ]; then
    install -m 0755 "$SCRIPT_DIR/bin/antseed-pi" "$PREFIX/bin/antseed-pi"
else
    curl -fsSL "https://raw.githubusercontent.com/CommunityPokeOrg/antseed-pi-termux/main/bin/antseed-pi" \
        -o "$PREFIX/bin/antseed-pi"
    chmod 0755 "$PREFIX/bin/antseed-pi"
fi

# --- 4. state dir + identity file ---------------------------------------------
mkdir -p "$ENV_DIR"
if [ ! -f "$ENV_DIR/env" ]; then
    umask 077
    printf '# AntSeed secp256k1 private key (hex, with or without 0x)\nANTSEED_IDENTITY_HEX=\n' > "$ENV_DIR/env"
    info "Created $ENV_DIR/env — add your ANTSEED_IDENTITY_HEX there (or let antseed-pi prompt on first run)."
fi
touch "$ENV_DIR/buyer.log"

# --- 5. pi extension ----------------------------------------------------------
info "Installing the AntSeed pi extension ($PI_ANTSEED_PKG)..."
if ! pi install "$PI_ANTSEED_PKG"; then
    warn "pi install failed — you can retry later with:  pi install $PI_ANTSEED_PKG"
    warn "or run pi with the extension once:  pi -e $PI_ANTSEED_PKG"
fi

info "Done. Next steps:"
cat <<'EOF'

  1. Add your identity key:   edit ~/.antseed-pi/env  (or let antseed-pi prompt)
  2. Optional but recommended:
       termux-wake-lock       # keep Android from killing the proxy
  3. Launch:                  antseed-pi
  4. In pi, pick a route:     /model antseed/<service-id>@<peer-prefix>
  5. Fund with USDC:          antseed buyer deposit   (or: antseed payments)
  6. Browse the network:      antseed network browse --services

  Helpers: antseed-pi status | stop | logs | peers
EOF
