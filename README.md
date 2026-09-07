# VRCOSC Linux Installer

An automated installer, updater, and launcher manager for running [VRCOSC](https://github.com/VolcanicArts/VRCOSC) on Linux (tested on Bazzite, SteamOS/Steam Deck, Fedora, and general Linux desktop environments).

## How it works

VRCOSC is a WPF application designed for Windows, requiring hardware graphics acceleration and direct integration with VRChat (using mDNS/OSCQuery protocols and local log parsing). 

This installer configures VRCOSC to run seamlessly by:
1. **Auto-detecting your VRChat Proton prefix** across multiple internal, secondary, and external storage drives (`libraryfolders.vdf`), with an interactive prompt fallback.
2. **Applying the WPF registry patch** to disable Direct3D acceleration, completely eliminating the black window / invisible context menu rendering bug under Wine/Proton.
3. **Silently provisioning .NET 10.0 Desktop Runtime** directly inside VRChat's Proton prefix (skips download if already installed).
4. **Installing VRCOSC binaries** into the prefix's AppData directory.
5. **Configuring firewall rules** for OSC/OSCQuery ports (9000, 9001, 5353 UDP).
6. **Setting up official application branding and desktop integration** (`vrcosc.png` hicolor icon, `vrcosc.desktop` launcher, and terminal command `vrcosc`).

## Prerequisites

Before running the installer, ensure you have:
* VRChat installed via Steam, and launched at least once under Proton.
* **Protontricks** installed (available on Bazzite/SteamOS by default, or via Flatpak).
* `curl` and `unzip` installed on the host system.

## Quick Install (One-Paste)

Copy and paste the following command into your terminal:

```bash
curl -sSL https://raw.githubusercontent.com/Bluscream/vrcosc-linux/main/install.sh | bash
```

## CLI Options & Usage

```bash
bash install.sh [OPTIONS]
```

| Option | Description |
| :--- | :--- |
| `-b, --backup` | Create a high-compression backup (`.7z` / `.tar.xz`) of VRCOSC configs & prefix registries to Desktop |
| `-f, --force` | Force re-download and reinstall of .NET 10 and VRCOSC binaries |
| `--branch <live\|beta>` | Choose release channel (`live` or `beta`, defaults to `live`) |
| `-u, --uninstall` | Cleanly remove VRCOSC binaries, launcher script, and desktop shortcut (preserves user settings) |
| `--dry-run` | Simulate actions without modifying files or installing runtimes |
| `--skip-firewall` | Skip firewall inspection and rule generation |
| `--prefix <PATH>` | Explicitly supply your custom VRChat compatdata/438100 path |
| `-h, --help` | Show command usage and options |

## Running VRCOSC

Once installed, you can launch VRCOSC:
* From your application menu/search bar (search for **VRCOSC**).
* Or by running the command in your terminal:
  ```bash
  vrcosc
  ```

## Community & Support

Ran into an issue or need assistance?
* Join the [VRCOSC Discord Server](https://discord.gg/vrcosc-1000862183963496519)
* Check the [Linux Discussion Thread](https://discord.com/channels/1000862183963496519/1466540047149957374)

## Credits & AI Disclaimer

This project was created and is maintained with the help of **Antigravity**, an agentic AI coding assistant designed by **Google DeepMind**.

*Disclaimer: The installation scripts and configuration modifications were generated and validated programmatically. Use at your own risk.*
