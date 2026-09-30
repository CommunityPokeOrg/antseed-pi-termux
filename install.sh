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

# --- 0. pick a fast repo mirror ----------------------------------------------
# packages.termux.dev can be very slow from some networks (~70 kB/s → a ~30 MB
# clang download takes >10 min). Probe a handful of official mirrors for real
# throughput and point apt at the fastest one before the big install. Fully
# non-interactive (safe under `curl | bash`): never reads stdin, never prompts.
# If probing fails — no curl, no network, every mirror dead — keep the
# configured default mirror.

MIRRORS=(
    https://packages.termux.dev/apt/termux-main
    https://packages-cf.termux.dev/apt/termux-main
    https://mirror.mwt.me/termux/main
    https://grimler.se/termux/termux-main
    https://ro.mirror.flokinet.net/termux/termux-main
    https://mirror.freedif.org/termux/termux-main
    https://mirrors.nguyenhoang.cloud/termux/termux-main
    https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main
    https://mirrors.ustc.edu.cn/termux/apt/termux-main
)

apt_deb_arch() {
    local a
    a="$(dpkg --print-architecture 2>/dev/null || true)"
    case "$a" in aarch64|arm|i686|x86_64) printf '%s' "$a"; return 0;; esac
    case "$(uname -m 2>/dev/null)" in
        aarch64)         echo aarch64 ;;
        arm*|*armv*)     echo arm ;;
        i?86)            echo i686 ;;
        x86_64)          echo x86_64 ;;
        *)               return 1 ;;
    esac
}

# Write $1 as the main-repo mirror, whichever apt layout this Termux has.
apply_termux_mirror() {
    local url="$1" apt_dir="$PREFIX/etc/apt"
    local mirror_cfg="$PREFIX/etc/termux/chosen_mirrors"
    # Newer termux-tools: sources use mirror+file:.../chosen_mirrors. The file
    # is a list tried in order — put the default back as a fallback entry.
    if grep -rqs 'mirror+file:.*chosen_mirrors' "$apt_dir" 2>/dev/null; then
        mkdir -p "$(dirname "$mirror_cfg")"
        printf '%s\n' "$url" > "$mirror_cfg"
        grep -qxF "${MIRRORS[0]}" "$mirror_cfg" || printf '%s\n' "${MIRRORS[0]}" >> "$mirror_cfg"
        return 0
    fi
    # Older installs: rewrite the `deb <url> stable main` line in sources.list.
    if [ -f "$apt_dir/sources.list" ] &&
       grep -qE '^deb[[:space:]]+https?://' "$apt_dir/sources.list"; then
        sed -i.bak -E \
            "s|^(deb[[:space:]]+)https?://[^[:space:]]+([[:space:]]+stable[[:space:]]+main.*)$|\1${url}\2|" \
            "$apt_dir/sources.list"
        return 0
    fi
    return 1
}

choose_fast_mirror() {
    command -v curl >/dev/null 2>&1 || return 1
    local arch tmp speed best_url="" best_speed=0 i
    arch="$(apt_deb_arch)" || return 1
    tmp="$(mktemp -d)" || return 1

    # Fetch the first 256 KiB of Packages.gz from every mirror in parallel and
    # record each one's download speed (bytes/s). curl -f means a failed probe
    # simply leaves no result file.
    for i in "${!MIRRORS[@]}"; do
        ( s="$(curl -fsSL --connect-timeout 4 --max-time 15 -r 0-262143 \
                  -o /dev/null -w '%{speed_download}' \
                  "${MIRRORS[$i]}/dists/stable/main/binary-${arch}/Packages.gz" \
                  </dev/null 2>/dev/null)" \
            && [ -n "$s" ] && printf '%s' "$s" > "$tmp/$i" ) &
    done
    wait

    for i in "${!MIRRORS[@]}"; do
        [ -s "$tmp/$i" ] || continue
        speed="$(cat "$tmp/$i")"
        if awk -v a="$speed" -v b="$best_speed" 'BEGIN { exit !(a > b) }'; then
            best_speed="$speed"; best_url="${MIRRORS[$i]}"
        fi
    done
    rm -rf "$tmp"
    [ -n "$best_url" ] || return 1
    apply_termux_mirror "$best_url" || return 1
    info "Using Termux mirror $best_url (~$(awk -v b="$best_speed" 'BEGIN { printf "%.0f", b/1024 }') KiB/s)"
}

info "Probing Termux mirrors for the fastest one..."
if ! choose_fast_mirror; then
    warn "Mirror probe failed or all mirrors unreachable — keeping the default mirror."
fi

# --- 1. Termux packages ------------------------------------------------------
info "Updating packages and installing dependencies (nodejs, git, jq, curl, termux-tools)..."
# When run via `curl | bash`, stdin is the script itself — any child that reads
# stdin (e.g. dpkg's conffile prompt for openssl.cnf) eats the rest of the
# script and the install silently stops. Force conffile defaults and detach
# stdin so no subprocess can consume the remaining script.
export DEBIAN_FRONTEND=noninteractive
DPKG_OPTS=(-o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold")
# python + make + clang + binutils: the node-gyp toolchain. Native modules like
# better-sqlite3 ship no android/arm64 prebuilds, so they compile from source.
pkg update -y </dev/null
apt-get "${DPKG_OPTS[@]}" install -y \
    nodejs git jq curl coreutils procps \
    python make clang binutils </dev/null

# --- 2. npm globals -----------------------------------------------------------
info "Installing @antseed/cli and @earendil-works/pi-coding-agent from npm..."
# Node's common.gypi android block references android_ndk_path; if node-gyp
# ever resolves upstream headers instead of Termux's shipped ones, gyp fails
# to parse without this define. Harmless when the variable is never referenced.
export GYP_DEFINES="${GYP_DEFINES:+$GYP_DEFINES }android_ndk_path=$PREFIX"
npm install -g @antseed/cli @earendil-works/pi-coding-agent </dev/null

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
        -o "$PREFIX/bin/antseed-pi" </dev/null
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
if ! pi install "$PI_ANTSEED_PKG" </dev/null; then
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
