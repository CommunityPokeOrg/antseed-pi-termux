#!/usr/bin/env bash
# tests/run.sh — offline test suite for the free-route picker.
#
# Boots a stub buyer proxy serving tests/fixtures/peers.json plus a stub
# buyer.state.json, then asserts on `antseed-pi-routes` output and on the
# `antseed-pi pick`/`antseed-pi models` launcher subcommands (with stub
# antseed/pi binaries on PATH).
#
# Usage: tests/run.sh

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP="$(mktemp -d)"
trap 'kill $STUB_PID 2>/dev/null; rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1" >&2; }
check() { # check <name> <haystack> <needle>
    if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else bad "$1 — expected '$3' in: $2"; fi
}
check_absent() {
    if printf '%s' "$2" | grep -qF "$3"; then bad "$1 — unexpected '$3'"; else ok "$1"; fi
}
check_eq() { # check_eq <name> <actual> <expected>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — got: $2 | want: $3"; fi
}

# ── stub proxy ───────────────────────────────────────────────────────────────
node tests/stub-proxy.mjs >"$TMP/port" 2>"$TMP/stub.err" &
STUB_PID=$!
for _ in $(seq 1 50); do grep -q '^PORT' "$TMP/port" 2>/dev/null && break; sleep 0.1; done
PORT="$(awk '{print $2}' "$TMP/port")"
[ -n "$PORT" ] || { cat "$TMP/stub.err" >&2; echo "stub proxy failed to start" >&2; exit 1; }

export ANTSEED_BASE_URL="http://127.0.0.1:$PORT"
export ANTSEED_BUYER_STATE_FILE="$ROOT/tests/fixtures/buyer.state.json"

ROUTES="node $ROOT/bin/antseed-pi-routes"

echo "── antseed-pi-routes (free, tsv) ──"
FREE_TSV="$($ROUTES --tsv)"
check_eq "free route count" "$(printf '%s\n' "$FREE_TSV" | grep -c .)" "2"
check    "free-llm id+rep+slug" "$FREE_TSV" "antseed/free-llm@aaaaaaaaaaaa-free-node-rep78"
check    "img-gen id"           "$FREE_TSV" "antseed/img-gen@eeeeeeeeeeee"
check_absent "paid excluded"    "$FREE_TSV" "paid-llm"
check_absent "unknown excluded" "$FREE_TSV" "unknown-llm"
check_absent "mixed excluded"   "$FREE_TSV" "mixed-llm"
check_absent "cached-fee excluded" "$FREE_TSV" "cached-fee"
check_absent "img-paid excluded"   "$FREE_TSV" "img-paid"
check_absent "partial excluded"    "$FREE_TSV" "partial-llm"
check_absent "bad peerId excluded" "$FREE_TSV" "ghost-llm"

echo "── antseed-pi-routes --all ──"
ALL_TSV="$($ROUTES --all --tsv)"
check_eq "all route count" "$(printf '%s\n' "$ALL_TSV" | grep -c .)" "8"
check "paid label"        "$ALL_TSV" "antseed/paid-llm@bbbbbbbbbbbb"
check "paid price"        "$ALL_TSV" '$0.5+$2/M'
check "unknown label"     "$ALL_TSV" "antseed/unknown-llm@cccccccccccc-rep9"
check "state rep wins"    "$ALL_TSV" "rep9"
check "mixed label"       "$ALL_TSV" 'free | $1+$1/M'
check "img price"         "$ALL_TSV" '$0.02/img'

echo "── sort order: rep desc ──"
FIRST_ID="$(printf '%s\n' "$ALL_TSV" | head -1 | cut -f1)"
check_eq "highest rep first" "$FIRST_ID" "antseed/free-llm@aaaaaaaaaaaa-free-node-rep78"

echo "── --json ──"
JSON="$($ROUTES --json)"
check_eq "json ids" "$(printf '%s' "$JSON" | grep -c '"id"')" "2"

echo "── --refresh ──"
$ROUTES --tsv --refresh >/dev/null && ok "refresh tolerated"

echo "── ANTSEED_MODELS allow-list ──"
ALLOWED="$(ANTSEED_MODELS='free-llm' $ROUTES --all --tsv)"
check_eq "allow-list narrows" "$(printf '%s\n' "$ALLOWED" | grep -c .)" "1"
check "allow-list id" "$ALLOWED" "antseed/free-llm@aaaaaaaaaaaa-free-node-rep78"

echo "── launcher e2e (stub antseed/pi) ──"
STUBBIN="$TMP/bin"; mkdir -p "$STUBBIN"
printf '#!/bin/sh\nexit 0\n' >"$STUBBIN/antseed"
printf '#!/bin/sh\necho "PI ARGS: $@"\n' >"$STUBBIN/pi"
chmod +x "$STUBBIN/antseed" "$STUBBIN/pi"

export ANTSEED_PI_HOME="$TMP/home"; mkdir -p "$ANTSEED_PI_HOME"
printf 'ANTSEED_IDENTITY_HEX=0000000000000000000000000000000000000000000000000000000000000001\n' >"$ANTSEED_PI_HOME/env"
chmod 600 "$ANTSEED_PI_HOME/env"

MODELS_OUT="$(PATH="$STUBBIN:$PATH" "$ROOT/bin/antseed-pi" models)"
check "models prints free route" "$MODELS_OUT" "antseed/free-llm@aaaaaaaaaaaa-free-node-rep78"
check_absent "models hides paid" "$MODELS_OUT" "paid-llm@"

if command -v script >/dev/null 2>&1; then
    PICK_OUT="$(printf '1\n' | PATH="$STUBBIN:$PATH" script -qec "$ROOT/bin/antseed-pi pick" /dev/null 2>/dev/null || true)"
    check "pick launches pi --model" "$PICK_OUT" "PI ARGS: --model antseed/free-llm@aaaaaaaaaaaa-free-node-rep78"
else
    printf '  skip pick e2e (no `script` for a pty)\n'
fi

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
