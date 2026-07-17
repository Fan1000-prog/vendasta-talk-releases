# VendastaTalk — Releases

Binary releases and the auto-update manifest for **VendastaTalk**, a
local-first dictation app for Vendasta staff. Source code lives in
Vendasta's private citizen-developer repo.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Fan1000-prog/vendasta-talk-releases/main/install.sh -o ~/Downloads/install.sh
bash ~/Downloads/install.sh
```

The script installs the speech engine, downloads the latest app from this
repo's releases, and sets everything up. After that the app **updates
itself** — you never come back here.

## What's in each release

| File | Purpose |
| --- | --- |
| `VendastaTalk_x.y.z_aarch64.dmg` | Fresh installs |
| `VendastaTalk_x.y.z_aarch64.app.tar.gz` (+ `.sig`) | Auto-updater bundle, minisign-signed |
| `latest.json` | Update manifest the app polls on launch |
