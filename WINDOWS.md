# Windows (x86_64) build of blockchain_module — unofficial

Community build by **yayguru**, not affiliated with or endorsed by the Logos project.
It packages the Logos blockchain node as a Logos Basecamp module for Windows 10/11 x64
(`windows-x86_64` variant), which the official release does not ship yet.

## What is in the package

| File | Built by | Notes |
|---|---|---|
| `blockchain_module_plugin.dll` | this flake, Nix MinGW cross (`logos-module-builder` / `mkWindowsPkgs`, Qt 6.11.1, GCC 15.2) | same toolchain as Basecamp 0.4.0 for Windows |
| `logos_blockchain.dll` | `logos-blockchain` 0.3.4 `c-bindings` crate (`logos-blockchain-c`), native MSYS2 MinGW64 + Rust `x86_64-pc-windows-gnu` | C++ runtime and winpthreads linked statically, imports only Windows system DLLs |
| `libfyaml.dll` | libfyaml 0.9.6, CMake build | |

Basecamp provides Qt, OpenSSL, libstdc++/libgcc/mcfgthread, zstd etc.

## Changes against upstream

Node (`logos-blockchain` 0.3.4, plus the patches of [logos-node-windows](https://github.com/yayguru/logos-node-windows)):

* `tracing/src/logging/local.rs`: the rolling log file's `<prefix>.latest` symlink is not created on Windows.
  Creating a symlink needs an elevated token or Developer Mode; without it the node panicked at start
  with `os error 1314`. Basecamp always configures file logging, so every normal user hit this.

Module (this repository, branch `windows-x86_64`):

* `flake.nix`: exposes the `x86_64-windows` cross target; links the prebuilt MinGW node library
  (the upstream Nix node build does not cross-compile to MinGW: rapidsnark/circuits).
* libfyaml for MinGW is built with its CMake build (the autotools build cannot target MinGW), with two fixes:
  * `cmake/generate-def.cmake`: `LIBRARY libfyaml` — the generated `.def` named the module `fyaml.dll`
    while the file is `libfyaml.dll`, so the plugin imported a DLL that does not exist.
  * `patches/libfyaml-0.9.6-cxx-atomics.patch`: the 0.9.6 public headers cannot be included from C++
    with g++ (C11 `_Atomic`); C++ now maps them onto `<atomic>`. Headers only.
* `metadata.json`: Windows runtime files; libfyaml as an external library on Windows only.

## Build

```sh
# 1. node library on Windows (MSYS2 MINGW64 + rustup x86_64-pc-windows-gnu), see logos-node-windows for the toolchain
cargo build -p logos-blockchain-c --release --target x86_64-pc-windows-gnu          # dependencies
cargo rustc -p logos-blockchain-c --lib --release --target x86_64-pc-windows-gnu -- -L native=C:/lb/staticlibs
#    C:/lb/staticlibs: libstdc++.dll.a / libwinpthread.dll.a / libpthread.dll.a = copies of the STATIC .a archives
# 2. package (Linux + Nix)
nix build .#packages.x86_64-windows.lgx-portable
lgx sign result/*.lgx --key yayguru.jwk --name yayguru --url https://github.com/yayguru
```

## Install

1. Install Logos Basecamp 0.4.0 for Windows.
2. Download `blockchain_module-0.3.4-windows-x86_64.lgx` and `blockchain_ui-0.3.5-windows-x86_64.lgx`
   from the [release](https://github.com/yayguru/logos-blockchain-module/releases/tag/v0.3.4-windows.1) and check `SHA256SUMS`.
3. Basecamp → Package Manager → **Install Local Package** → pick the module `.lgx`, then the UI `.lgx`.
   Basecamp says the publisher is not trusted yet: expected, the packages are signed by yayguru's own key
   (`did:jwk:eyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6InRpMUIwVG5nODRHTU5wTThCOXNsZmZUSmdJWVJMWHlsNVppOFBiQ2daMW8ifQ`),
   not by Logos. Choose **Install** (or **Trust & install** to trust yayguru for later updates).
4. Applications → **Blockchain** → Set up your node.

Notes

* **Another node on the same PC?** "Generate a new node" uses the default ports (UDP 3000, HTTP 127.0.0.1:8080).
  If a standalone node already uses them, generate the config with other ports (or edit `net_port`/blend port/`http`
  listen address in `user_config.yaml`) and use "Use an existing config".
* Windows Firewall asks about `logos_host.exe` on first start; allowing private networks improves inbound connectivity,
  the node also works outbound-only.

## Tested

Windows 10 x64, Basecamp 0.4.0-rc.2 (per-user install, no admin), 14 Nov 2026:
package installed through Package Manager, node started from the Blockchain app,
`/cryptarchia/info` height 1811 and climbing (initial block download), `/network/info` 121 peers / 124 connections.
Also tested headless with `logosctl` 0.3.2 for Windows (install, load, generate_user_config, start).
