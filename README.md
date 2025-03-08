# SeamlessMC
![](https://s3.gifyu.com/images/bbcM0.gif)

A lightweight, Docker-based solution for hosting private Minecraft servers among friends without renting dedicated servers. SeamlessMC leverages Docker, Tailscale, and GitHub to:

- **Spin up** a private server on any machine.
- **Preserve** server data via GitHub for easy version control.
- **Switch hosts** effortlessly among friends.
- **Securely connect** using Tailscale, skipping complex networking.

## Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation and Setup](#installation-and-setup)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Features
- **Dockerized** for consistency.
- **Automatic data syncing** to GitHub.
- **Tailscale integration** for easy private networking.
- **Modpack support** — just provide a ZIP URL.

## Prerequisites
1. [Docker](https://www.docker.com/)
2. [Tailscale](https://tailscale.com/) & [Tailscale API key](https://login.tailscale.com/admin/settings/keys)
3. [GitHub repository](https://github.com/) & [personal access token](https://github.com/settings/tokens)
4. Hosted Modpack ZIP (e.g., from [CurseForge](https://www.curseforge.com/minecraft/search?page=1&pageSize=20&sortBy=relevancy&class=modpacks) “Server Packs”)

## Installation and Setup
1. **Download** this repository
2. **Configure** environment:
   - [GitHub repo](https://github.com/) named "minecraft_data" & [token](https://github.com/settings/tokens)
   - Tailscale installed & authenticated
   - [Tailscale API key](https://login.tailscale.com/admin/settings/keys)
   - Modpack ZIP URL
3. **Deploy**:
   - **Linux/macOS**: `./deploy.sh`
   - **Windows**: `.\deploy.ps1`
   - Follow prompts for missing environment variables.

## Usage
1. **Start the Server**
   - Access [http://localhost:4000/](http://localhost:4000/) in your browser.
   - Enter Tailscale API key, Modpack URL, etc.
   - Click **Start**; share the displayed IP with friends.
2. **Stop the Server**
   - Click **Stop** in the web UI to push changes to GitHub.
   - In your terminal, press `Ctrl + C` to shut down containers.
3. **Transfer Hosting**
   - Share the `env` file with the next host.
   - They run the same deploy script and start the server.
4. **Change Modpack**
   - Run `cleanup.sh` (or `cleanup.ps1` on Windows).
   - Repeat the setup steps above with your new Modpack ZIP URL.

## Troubleshooting
- **Containers won’t start**: Check Docker is running; ensure ports 4000/6379 are free.
- **Tailscale errors**: Validate the API key; ensure Tailscale is installed and logged in.
- **Data not saving**: Always **Stop** the server in the web UI before stopping containers.
