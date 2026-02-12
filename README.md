# sky1-linux-build

Build tooling and development scripts for Sky1 Linux kernels.

## Overview

This repository contains scripts to build kernel .deb packages for CIX Sky1 SoC
using the kernel's built-in `make bindeb-pkg` system, plus development tools for
kernel config management, dev builds, and upstream tracking.

Patches and config are sourced from the [linux-sky1](https://github.com/Sky1-Linux/linux-sky1)
repository (sibling directory).

## Prerequisites

```bash
sudo apt install build-essential bc bison flex libelf-dev libssl-dev \
    debhelper dh-exec rsync cpio kmod
```

## Build Kernel Packages

### LTS (tarball-based)

```bash
# 1. Prepare source (download + patch)
./scripts/prepare-source.sh 6.18.9

# 2. Build packages
./scripts/build-debs.sh 6.18.9 1 sky1
#                       ^      ^ ^
#                       |      | +-- variant (sky1, sky1-latest, sky1-rc, etc.)
#                       |      +---- revision number
#                       +----------- kernel version

# 3. Upload to APT
./scripts/upload-to-apt.sh build ~/sky1-linux-distro/apt-repo sid main 6.18.9
```

### Latest / RC / Next (git-based)

```bash
# Latest stable
./scripts/prepare-source-git.sh v6.19 latest
./scripts/build-debs.sh 6.19 1 sky1-latest
./scripts/upload-to-apt.sh build ~/sky1-linux-distro/apt-repo sid latest 6.19

# RC
./scripts/prepare-source-git.sh v7.0-rc1 rc
./scripts/build-debs.sh 7.0-rc1 1 sky1-rc
./scripts/upload-to-apt.sh build ~/sky1-linux-distro/apt-repo sid rc 7.0.0-rc1
```

### Export Patches from Development Tree

When you have new patches in `~/mainline-linux/`:

```bash
./scripts/export-patches.sh ~/mainline-linux
# Patches are exported to ../linux-sky1/patches/
```

## Build Variants

| Variant | Config | Track | Description |
|---------|--------|-------|-------------|
| `sky1` | `config.sky1` | LTS | Production kernel (v6.18.x) |
| `sky1-latest` | `config.sky1-latest` | Latest | Latest stable (v6.19.x) |
| `sky1-rc` | `config.sky1-rc` | RC | Release candidates |
| `sky1-next` | `config.sky1-next` | Next | Bleeding edge |
| `sky1-dev` | `config.sky1-dev` | — | Debug-enabled kernel |

## Development Tools

These scripts are also symlinked into `~/mainline-linux/scripts/` for convenience.

| Script | Purpose |
|--------|---------|
| `build-install.py` | Dev kernel build + install to EFI partition |
| `build-test.py` | Compile smoke tests (allyesconfig, allmodconfig, etc.) |
| `kernel-track-status.py` | Query upstream for new kernel releases |
| `update-dev-boot.py` | Auto-generate GRUB dev boot entries from local branches |
| `manage-config.py` | Set/show/remove config options across all tracks and policy |
| `reconcile-configs.py` | Cross-track config validation against policy |
| `sky1_lib.py` | Shared library (board detection, version parsing, git helpers) |

### Config Management

```bash
# Set a config option across all tracks (dry-run by default)
./scripts/manage-config.py set USB_UAS=m \
    --policy usb --doc "USB Support" --type module --desc "USB Attached SCSI" --apply

# Show current state of an option across all tracks
./scripts/manage-config.py show USB_UAS

# Validate all track configs against policy
./scripts/reconcile-configs.py
```

## Directory Structure

```
sky1-linux-build/
├── scripts/
│   ├── prepare-source.sh      # Download kernel tarball + apply patches (LTS)
│   ├── prepare-source-git.sh  # Clone kernel git + apply patches (Latest/RC/Next)
│   ├── build-debs.sh          # Run make bindeb-pkg
│   ├── upload-to-apt.sh       # reprepro integration
│   ├── export-patches.sh      # Export patches from mainline-linux
│   ├── build-install.py       # Dev kernel build + install
│   ├── build-test.py          # Compile smoke tests
│   ├── kernel-track-status.py # Upstream release tracker
│   ├── update-dev-boot.py     # GRUB dev entry generator
│   ├── manage-config.py       # Config option manager
│   ├── reconcile-configs.py   # Cross-track config validator
│   └── sky1_lib.py            # Shared Python library
├── meta/                      # Metapackage sources (future)
│   └── debian/
└── build/                     # Build output (gitignored)
    └── *.deb
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LINUX_SKY1` | `../linux-sky1` | Path to linux-sky1 repo |

## Related Repositories

- [linux-sky1](https://github.com/Sky1-Linux/linux-sky1) - Patches and config
- [linux](https://github.com/Sky1-Linux/linux) - Full kernel source (development happens here)
- [apt](https://github.com/Sky1-Linux/apt) - APT repository
