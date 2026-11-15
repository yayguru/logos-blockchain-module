# Logos Blockchain Module

A Logos core module that wraps the [logos-blockchain](https://github.com/logos-blockchain/logos-blockchain) C bindings.

## Windows (unofficial yayguru build)

Branch `windows-x86_64` of this fork builds the module for Logos Basecamp on Windows 10/11 x64.
Users: download the `.lgx` from the newest [release](https://github.com/yayguru/logos-blockchain-module/releases)
and follow the **[user guide](https://github.com/yayguru/logos-blockchain-ui/blob/windows-x86_64/WINDOWS.md)**
(install module first, then the UI). Build details and changes against upstream: [WINDOWS.md](WINDOWS.md).
Community build, not an official Logos release.

### Build and inspect

```bash
nix build '.#lgx'
```
