# Raspberry Pi 5 — Full Setup Guide
## Ubuntu 24.04 LTS + GNOME + RustDesk + Dev Tools

---

## Table of Contents

1. [Flash Ubuntu 24.04 LTS](#step-1--flash-ubuntu-2404-lts-desktop)
2. [First Boot & Update](#step-2--first-boot--update)
3. [Install Tailscale](#step-3--install-tailscale)
4. [Disable Wayland (Switch to X11)](#step-4--disable-wayland-switch-to-x11)
5. [Enable Auto-login](#step-5--enable-auto-login)
6. [Reboot and Verify X11](#step-6--reboot-and-verify-x11)
7. [Remote Desktop via RustDesk](#step-7--remote-desktop-via-rustdesk)
8. [Mount Google Drive with rclone](#step-8--mount-google-drive-with-rclone)
9. [Install Node.js and npm](#step-9--install-nodejs-and-npm)
10. [Install Claude Code](#step-10--install-claude-code)
11. [Install Playwright](#step-11--install-playwright)
12. [Set Up Git & GitHub](#step-12--set-up-git--github)
13. [Troubleshooting](#troubleshooting)

---

## Step 1 — Flash Ubuntu 24.04 LTS Desktop

Use **Raspberry Pi Imager** on your Mac:
- Download from [raspberrypi.com/software](https://www.raspberrypi.com/software/)
- Choose OS → **Other general-purpose OS → Ubuntu → Ubuntu Desktop 24.04 LTS (64-bit)**
- Before writing, click the ⚙️ settings icon and configure:
  - Hostname (e.g. `avil-rpi5`)
  - Username and password
  - WiFi credentials
  - Enable SSH ✅

> **Why Ubuntu 24.04 LTS and not later?** Ubuntu 25.10 dropped X11 GNOME sessions entirely, which breaks all remote desktop tools. 24.04 LTS supports X11, is stable, and supported until 2029.

---

## Step 2 — First Boot & Update

SSH in once it's up:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Step 3 — Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

Note the Tailscale IP — you'll use it to connect remotely. RustDesk will connect directly over Tailscale with no relay servers needed.

---

## Step 4 — Disable Wayland (Switch to X11)

Ubuntu 24.04 uses Wayland by default, which blocks remote desktop tools. Switch to X11:

```bash
sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
```

Verify it took:

```bash
grep WaylandEnable /etc/gdm3/custom.conf
# Should return: WaylandEnable=false
```

---

## Step 5 — Enable Auto-login

Required so the desktop session starts on boot without a physical keyboard or monitor:

```bash
sudo vi /etc/gdm3/custom.conf
```

Add under `[daemon]`:

```ini
AutomaticLoginEnable=true
AutomaticLogin=avil
```

---

## Step 6 — Reboot and Verify X11

```bash
sudo reboot
```

SSH back in and confirm X11 is running:

```bash
loginctl list-sessions
loginctl show-session 1 | grep Type
# Should return: Type=x11
```

---

## Step 7 — Remote Desktop via RustDesk

RustDesk connects to the **live GNOME session** (same desktop you'd see on a physical monitor). It uses modern video codecs (H264/VP9) for good performance over Tailscale.

> **Why RustDesk and not xrdp?** xrdp creates a separate X session and struggles to launch GNOME properly. RustDesk attaches to the existing live session, which is what we want.

### Install RustDesk

```bash
# Get the latest ARM64 build URL
curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
  | grep browser_download_url \
  | grep aarch64 \
  | grep '\.deb' \
  | grep -v server

# Download and install (replace version number with latest from above)
wget https://github.com/rustdesk/rustdesk/releases/download/1.4.6/rustdesk-1.4.6-aarch64.deb
sudo dpkg -i rustdesk-*.deb
sudo apt-get install -f -y
```

### Disable the system RustDesk service

The system service (running as root) overwrites the config file on start. Disable it and use a user service instead:

```bash
sudo systemctl disable rustdesk
sudo systemctl stop rustdesk
```

### Configure for direct IP access

```bash
vi ~/.config/rustdesk/RustDesk2.toml
```

Add under `[options]`:

```
direct-server = "Y"
direct-access-port = "21118"
```

### Set a password

```bash
/usr/share/rustdesk/rustdesk --password yourpassword
```

### Set up autostart as a user systemd service

```bash
mkdir -p ~/.config/systemd/user
vi ~/.config/systemd/user/rustdesk.service
```

Paste this content:

```ini
[Unit]
Description=RustDesk Remote Desktop
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/avil/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/bin/rustdesk --service
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

Enable and start:

```bash
systemctl --user enable rustdesk.service
systemctl --user start rustdesk.service
```

Allow it to run without being logged in:

```bash
sudo loginctl enable-linger avil
```

Verify it's listening:

```bash
sudo ss -tlnp | grep 21118
# Should show LISTEN on port 21118
```

### Connect from Mac

- Install RustDesk: `brew install --cask rustdesk`
- Open RustDesk
- Enter the Pi's **Tailscale IP** in the connection box
- Enter your password
- Full live GNOME desktop ✅

### Connect from Android

- Install **RustDesk** from the Play Store
- Same — enter Tailscale IP and password

### RustDesk performance settings (Mac client)

In RustDesk Settings → Display:
- **Default image quality:** Optimize reaction time
- **Default codec:** H264
- **Default view style:** Scale adaptive

> **Performance tip:** Close Firefox on the Pi during remote sessions — it uses significant CPU which competes with screen encoding. Use Chromium instead for lighter browsing.

---

## Step 8 — Mount Google Drive with rclone

### Install rclone

```bash
sudo apt-get install -y rclone
```

### Get a Google API Client ID (for better performance & rate limits)

Using your own Client ID avoids rclone's shared API quota:

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a new project (or select an existing one)
3. Go to **APIs & Services → Library**
4. Search for and enable **Google Drive API**
5. Go to **APIs & Services → OAuth consent screen**
   - Choose **External**, fill in app name and your email
   - Add scope: `https://www.googleapis.com/auth/drive`
   - Add your email as a test user
6. Go to **APIs & Services → Credentials → Create Credentials → OAuth Client ID**
   - Application type: **Desktop app**
   - Note down the **Client ID** and **Client Secret**

### Configure rclone

```bash
rclone config
```

Follow the prompts:
- `n` for new remote
- Name it `Google-Drive`
- Storage type: `drive` (Google Drive)
- Enter your Client ID and Client Secret from above
- Scope: `drive` (full access)
- Leave root folder ID blank
- Auto config: `y` — a browser will open, log in and authorize
- Team drive: `n`
- Confirm with `y`

### Create mount point and mount

```bash
mkdir -p ~/GoogleDrive
rclone mount Google-Drive: ~/GoogleDrive --vfs-cache-mode writes --daemon
```

Verify it's working:

```bash
ls ~/GoogleDrive
```

### Auto-mount on boot via systemd

```bash
mkdir -p ~/.config/systemd/user
vi ~/.config/systemd/user/rclone-gdrive.service
```

Paste this content:

```ini
[Unit]
Description=RClone Google Drive Mount
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount Google-Drive: /home/avil/GoogleDrive \
  --vfs-cache-mode writes \
  --file-perms 0755 \
  --log-level INFO
ExecStop=/bin/fusermount -u /home/avil/GoogleDrive
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Enable and start:

```bash
systemctl --user enable rclone-gdrive.service
systemctl --user start rclone-gdrive.service
systemctl --user status rclone-gdrive.service
```

Allow it to run without being logged in:

```bash
sudo loginctl enable-linger avil
```

> **Note:** Google Drive doesn't support Unix file permissions. The `--file-perms 0755` flag makes all files appear executable, but permissions aren't actually stored in Google Drive. For scripts, keep them in a local folder or git repo instead.

---

## Step 9 — Install Node.js and npm

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version
npm --version
```

---

## Step 10 — Install Claude Code

> **Requirements:** An Anthropic account with Claude Max subscription or API access.

### Install

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

### ARM64 note (Raspberry Pi)

The native installer may have issues with ARM64/aarch64. If it fails, use npm instead:

```bash
npm install -g @anthropic-ai/claude-code
```

### Authenticate

```bash
claude
```

On first launch it will give you a URL. Since you're on SSH:
- Copy the URL and open it on your Mac
- Log in with your Anthropic account
- Copy the authentication code back into the terminal

### Alternative — copy credentials from Mac

If OAuth fails on the Pi (known ARM64 issue), authenticate on your Mac first then copy credentials over:

```bash
# On your Mac (after running `claude` and authenticating):
scp ~/.claude/.credentials.json avil@<tailscale-ip>:~/.claude/.credentials.json

# On the Pi, mark onboarding as complete:
vi ~/.claude.json
# Set: "hasCompletedOnboarding": true
```

### Verify

```bash
claude --version
```

---

## Step 11 — Install Playwright

Playwright is a browser automation framework for Node.js.

### Install per-project (recommended)

```bash
mkdir ~/myproject && cd ~/myproject
npm init -y
npm install playwright
```

### Or install globally

```bash
npm install -g playwright
```

### Install browsers

```bash
npx playwright install chromium
```

> **Note:** On ARM64 (Raspberry Pi), Chromium has the best support. Firefox and WebKit may not have prebuilt ARM64 binaries.

### Install system dependencies

```bash
npx playwright install-deps chromium
```

### Verify

```bash
npx playwright --version
```

---

## Step 12 — Set Up Git & GitHub

### Install git

```bash
sudo apt-get install -y git
```

### Configure your identity

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
git config --global init.defaultBranch main
```

### Create a GitHub account

Go to [github.com](https://github.com) and sign up for a free account. Free accounts include:
- Unlimited public and private repos
- Up to 1GB per repo (soft limit), 100MB max per file
- No limit on number of repos

### Set up SSH key for passwordless access

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your@email.com"

# Show the public key
cat ~/.ssh/id_ed25519.pub
```

Go to [github.com/settings/keys](https://github.com/settings/keys) → **New SSH key** → paste the key.

Test the connection:

```bash
ssh -T git@github.com
# Should return: Hi username! You've successfully authenticated.
```

### Create your first repo

On GitHub, click **New repository**, name it (e.g. `scripts`), set to private, create it.

Then on the Pi:

```bash
mkdir ~/scripts
cd ~/scripts
git init
git remote add origin git@github.com:yourusername/scripts.git
```

### Daily workflow

```bash
# Stage and save a snapshot of your changes
git add .
git commit -m "describe what you changed"

# Push to GitHub
git push

# On another machine, get latest changes
git pull
```

### Clone an existing repo

```bash
git clone git@github.com:yourusername/repo-name.git
```

### Suggested repo structure

Keep separate repos for separate projects:

```
github.com/yourusername/
├── my-website/          # website code
├── wordpress-plugins/   # your plugins
└── scripts/             # Pi scripts and automation
```

> **Tip:** Use git for code and scripts. Use Google Drive for documents, media, and assets. That's the cleanest separation.

---

## Troubleshooting

### RustDesk not listening on port 21118
```bash
# Check config is correct
cat ~/.config/rustdesk/RustDesk2.toml
# Restart user service
systemctl --user restart rustdesk.service
# Verify
sudo ss -tlnp | grep 21118
```

### RustDesk shows wrong password
```bash
/usr/share/rustdesk/rustdesk --password yournewpassword
systemctl --user restart rustdesk.service
```

### RustDesk image is blurry
In RustDesk Settings → Display on the Mac client:
- Set **Default view style** to **Scale adaptive**
- Set **Default codec** to **H264**
- Set **Default image quality** to **Optimize reaction time**

### RustDesk is slow
- Close Firefox on the Pi (it competes heavily with screen encoding)
- Switch codec to H264 in client settings
- Check CPU usage on Pi: `top`

### Two RustDesk instances running
```bash
sudo kill $(pgrep rustdesk)
sleep 2
systemctl --user start rustdesk.service
```

### rclone mount not working after reboot
```bash
systemctl --user status rclone-gdrive.service
# If stopped, unmount and restart:
fusermount -u ~/GoogleDrive
systemctl --user restart rclone-gdrive.service
```

### Claude Code auth fails on ARM64
```bash
# Install older known-working version
npm install -g @anthropic-ai/claude-code@0.2.114
```

### X11 session not starting
```bash
# Confirm X11 is active
loginctl show-session 1 | grep Type
# Should return Type=x11
# If not, verify /etc/gdm3/custom.conf has WaylandEnable=false
```

### Tailscale not connecting
```bash
sudo tailscale status
sudo tailscale up --reset
```

### Enable SSH (if not already enabled)
```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```
