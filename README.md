# antseed-pi-termux

Launcher for running the **pi** coding agent (`@earendil-works/pi-coding-agent`)
on the **AntSeed** network inside **Termux** on Android.

It installs everything you need, starts the AntSeed buyer proxy on
`http://localhost:8377`, loads the [pi-antseed](https://github.com/AntSeed/pi-antseed)
extension, and drops you into pi with every discovered AntSeed route available
in the model selector.

## What you get

- `install.sh` — one-shot installer for all dependencies (Termux packages, npm
  CLIs, the launcher, the pi extension).
- `antseed-pi` — launcher on your `$PATH`: starts the buyer proxy if it isn't
  running, waits for it to answer, then execs `pi`. Also manages the proxy
  (`status` / `stop` / `logs` / `peers`).

## Prerequisites

- **Termux** installed from [F-Droid](https://f-droid.org/en/packages/com.termux/)
  or the [GitHub releases](https://github.com/termux/termux-app/releases) page.
  Do **not** use the Play Store build — it's outdated and unmaintained.
- Android 7+ recommended; a few hundred MB of free storage.
- An **AntSeed identity**: a secp256k1 private key in hex (`ANTSEED_IDENTITY_HEX`).
- USDC on **Base** to pay providers — deposit after install
  (`antseed buyer deposit` or `antseed payments`).

## Install

```bash
pkg update -y && pkg install -y git
git clone https://github.com/CommunityPokeOrg/antseed-pi-termux
cd antseed-pi-termux
./install.sh
```

One-shot alternative (installs the launcher without cloning):

```bash
curl -fsSL https://raw.githubusercontent.com/CommunityPokeOrg/antseed-pi-termux/main/install.sh | bash
```

The installer:

1. `pkg`/`apt-get install`s `nodejs`, `git`, `jq`, `curl`, `coreutils`, `procps`
   plus the node-gyp toolchain (`python`, `make`, `clang`, `binutils`) —
   `better-sqlite3` has no android/arm64 prebuild and compiles from source
2. `npm install -g @antseed/cli @earendil-works/pi-coding-agent`
3. installs `bin/antseed-pi` to `$PREFIX/bin/antseed-pi`
4. creates `~/.antseed-pi/env` for your identity
5. runs `pi install git:github.com/AntSeed/pi-antseed` so the extension loads
   every time pi starts

## Configure your identity

Either edit `~/.antseed-pi/env`:

```bash
ANTSEED_IDENTITY_HEX=<your-private-key-hex>
```

or just run `antseed-pi` — it prompts for the key on first run and saves it
(mode `0600`). You can also `export ANTSEED_IDENTITY_HEX=...` in your shell.

## Run

```bash
termux-wake-lock   # recommended: stops Android killing the proxy
antseed-pi
```

Then inside pi open the model selector (`Ctrl+L` or `/model`) and pick a route:

```
antseed/<service-id>@<peer-prefix>[-<peer-name>][-rep<score>]
# e.g. antseed/minimax-m2.7@bbbbbbbbbbbb-rep5
```

Routes are discovered from `/_antseed/peers` and ordered by peer reputation.
To restrict what's offered, set e.g.
`ANTSEED_MODELS="minimax-m2.7,arcee-trinity-thinking"` before launching.

Anything you pass to `antseed-pi` that isn't a subcommand is forwarded to `pi`
(`antseed-pi --help`, `antseed-pi -p "hello"`, ...). Use `antseed-pi -- <args>`
to force passthrough.

### Helper commands

| Command | What it does |
| --- | --- |
| `antseed-pi` / `antseed-pi start` | start proxy if needed + launch pi |
| `antseed-pi status` | proxy / identity / CLI status |
| `antseed-pi stop` | stop the managed buyer proxy |
| `antseed-pi logs [N]` | tail the proxy log (`~/.antseed-pi/buyer.log`) |
| `antseed-pi peers` | pretty-print `/_antseed/peers` |

### Useful antseed commands

```bash
antseed network browse --services      # who's on the network + pricing
antseed buyer status                   # connection + deposit state
antseed buyer balance                  # USDC balance
antseed buyer deposit                  # funding address + QR
antseed payments                       # local funding portal on :3118
```

## How it works

`antseed buyer start` runs a buyer proxy on `127.0.0.1:8377` — it handles peer
discovery, routing, payment channels, and protocol adaptation. The pi-antseed
extension registers an `antseed` provider in pi, reads each peer's advertised
API protocol from `/_antseed/peers`, registers every service/peer pair as a pi
model, and sends `x-antseed-pin-peer: <peer>` on each request. You never need a
session-wide `antseed buyer connection set` pin.

## Configuration

| Env var | Default | Purpose |
| --- | --- | --- |
| `ANTSEED_IDENTITY_HEX` | — (required) | secp256k1 buyer identity key |
| `ANTSEED_BASE_URL` | `http://localhost:8377` | buyer proxy URL |
| `ANTSEED_API_KEY` | unset | only if the proxy sits behind auth |
| `ANTSEED_MODELS` | all discovered | comma-separated route/service allow-list |
| `ANTSEED_PI_HOME` | `~/.antseed-pi` | launcher state dir (env, pid, log) |
| `ANTSEED_PI_READY_TIMEOUT` | `60` | seconds to wait for the proxy |

## Troubleshooting

- **Android kills the proxy in the background** → run `termux-wake-lock`, and
  disable battery optimization for Termux in system settings.
- **`antseed-pi` dies with "antseed buyer start failed"** →
  `antseed-pi logs` for the proxy log; check `ANTSEED_IDENTITY_HEX` is set.
- **No `antseed/...` models in pi** → proxy isn't up or sees no peers:
  `antseed-pi status`, `antseed network browse --services`, then `/reload`
  in pi.
- **`Connection state: idle` in `antseed buyer status`** → the proxy isn't
  running; launch via `antseed-pi` or run `antseed buyer start` yourself.
- **Insufficient deposits** → `antseed buyer balance`; top up with
  `antseed buyer deposit`.
- **5xx on a request** → the pinned peer went offline; re-run
  `antseed-pi peers`, `/reload`, pick another route.
- **npm install fails on old Android** → `pkg upgrade nodejs` or switch to
  `pkg install nodejs-lts`.

## References

- [AntSeed — Using the API](https://antseed.com/docs/guides/using-the-api/)
- [AntSeed/pi-antseed](https://github.com/AntSeed/pi-antseed) — the pi extension
- [pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)

## License

MIT
