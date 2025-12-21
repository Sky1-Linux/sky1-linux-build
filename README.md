# sky1-linux-build

Build tooling for Sky1 Linux kernel packages.

## Overview

This repository contains scripts to build kernel .deb packages for CIX Sky1 SoC
using the kernel's built-in `make bindeb-pkg` system.

Patches and config are sourced from the [linux-sky1](https://github.com/Sky1-Linux/linux-sky1)
repository (sibling directory).

## Prerequisites

```bash
sudo apt install build-essential bc bison flex libelf-dev libssl-dev \
    debhelper dh-exec rsync cpio kmod
```

## Usage

### Build Kernel Packages

```bash
# 1. Prepare source (download + patch)
./scripts/prepare-source.sh 6.18.2

# 2. Build packages
./scripts/build-debs.sh 6.18.2 1 sky1
#                       ^      ^ ^
#                       |      | +-- variant (sky1 or sky1-dev)
#                       |      +---- revision number
#                       +----------- kernel version

# Packages are in build/
ls build/*.deb
```

### Upload to APT Repository

```bash
./scripts/upload-to-apt.sh build ~/sky1-linux-distro/apt-repo sid
```

### Export Patches from Development Tree

When you have new patches in `~/mainline-linux/`:

```bash
./scripts/export-patches.sh ~/mainline-linux
# Patches are exported to ../linux-sky1/patches/
```

## Build Variants

| Variant | Config | Description |
|---------|--------|-------------|
| `sky1` | `config.sky1` | Production kernel |
| `sky1-dev` | `config.sky1-dev` | Debug-enabled kernel |

## Directory Structure

```
sky1-linux-build/
├── scripts/
│   ├── prepare-source.sh    # Download kernel + apply patches
│   ├── build-debs.sh        # Run make bindeb-pkg
│   ├── upload-to-apt.sh     # reprepro integration
│   └── export-patches.sh    # Export patches from mainline-linux
├── meta/                    # Metapackage sources (future)
│   └── debian/
└── build/                   # Build output (gitignored)
    └── *.deb
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LINUX_SKY1` | `../linux-sky1` | Path to linux-sky1 repo |

## Related Repositories

- [linux-sky1](https://github.com/Sky1-Linux/linux-sky1) - Patches and config
- [apt](https://github.com/Sky1-Linux/apt) - APT repository
