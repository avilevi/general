# Raspberry Pi 5 — Full Setup Guide
## Ubuntu 24.04 LTS + GNOME + Remote Desktop + Dev Tools

---

## Table of Contents

1. [Flash Ubuntu 24.04 LTS](#step-1--flash-ubuntu-2404-lts-desktop)
2. [First Boot & Update](#step-2--first-boot--update)
3. [Install Tailscale](#step-3--install-tailscale)
4. [Disable Wayland (Switch to X11)](#step-4--disable-wayland-switch-to-x11)
5. [Enable Auto-login](#step-5--enable-auto-login)
6. [Reboot and Verify X11](#step-6--reboot-and-verify-x11)
7. [Remote Desktop via xrdp](#step-7--remote-desktop-via-xrdp)
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

Note the Tailscale IP — you'll use it to connect remotely.

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

## Step 7 — Remote Desktop via xrdp

xrdp uses Microsoft's RDP protocol — best performance for desktop use, and works natively with the free Microsoft Remote Desktop app on Mac and Android.

### Install xrdp

```bash
sudo apt-get install -y xrdp
sudo systemctl enable xrdp
sudo systemctl start xrdp
```

### Fix the black screen issue (common with GNOME)

```bash
echo "gnome-session" > ~/.xsession
sudo sed -i 's/port=3389/port=3389\nuse_vsock=false/' /etc/xrdp/xrdp.ini
sudo systemctl restart xrdp
```

### Verify it's listening

```bash
sudo ss -tlnp | grep 3389
# Should show LISTEN on port 3389
```

### Connect from Mac

- Install **Microsoft Remote Desktop** from the Mac App Store (free)
- Add a new PC with your Pi's Tailscale IP
- Username: `avil`, password: your Pi password
- Full GNOME desktop ✅

### Connect from Android

- Install **Microsoft Remote Desktop** from the Play Store (free)
- Same — add PC with Tailscale IP, username and password

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

### xrdp shows black screen on connect
```bash
echo "gnome-session" > ~/.xsession
sudo systemctl restart xrdp
```

### xrdp not listening on port 3389
```bash
sudo systemctl status xrdp
sudo ss -tlnp | grep 3389
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
