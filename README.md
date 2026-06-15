# VRCOSC Linux Installer

An automated installer and launch script wrapper for running [VRCOSC](https://github.com/VolcanicArts/VRCOSC) on Linux (specifically tested on Bazzite, SteamOS/Steam Deck, and general Linux desktop environments).

## How it works

VRCOSC is a WPF application designed for Windows, requiring hardware graphics acceleration and direct integration with VRChat (using mDNS/OSCQuery protocols and local log parsing). 

This installer configures VRCOSC to run seamlessly by:
1. Locating your existing VRChat Steam/Proton prefix.
2. Ingesting the required registry patch directly into the prefix to disable WPF hardware graphics acceleration (fixing the black window/context menu/tooltip rendering bugs).
3. Automatically finding and installing the necessary Windows-version **.NET 10.0 Desktop Runtime** inside the VRChat prefix silently.
4. Fetching the latest official build of VRCOSC, unzipping the binaries directly into the VRChat prefix's local AppData folder.
5. Creating a launch wrapper (`vrcosc`) and a desktop entry shortcut (`vrcosc.desktop`) so you can search for and launch the app normally.

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

## Running VRCOSC

Once installed, you can launch VRCOSC:
* From your application menu/search bar (search for **VRCOSC**).
* Or by running the command in your terminal:
  ```bash
  vrcosc
  ```
