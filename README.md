# aptx

Create isolated Ubuntu environments for APT package management.

**Goal**: Provide isolated, reproducible Ubuntu environments for APT packages, completely separated from system packages with global package access, ensuring consistent builds across different systems.

## Quick Start

```bash
# Initialize environment
aptx init

# Enter environment
aptx shell

# Install packages
apt install <package>

# Exit environment
exit
```

## Modes

**Isolated** (default): Completely isolated environment
```bash
aptx init
```

**Overlay**: Can access system packages when not available locally
```bash
aptx init --mode=overlay
```

## Global Packages

Install packages globally for system-wide access:

```bash
# Initialize global environment
aptx global init

# Install global package
aptx global install <package>

# Package is now available everywhere
```

Global packages are automatically accessible in local overlay environments.

## Commands

- `aptx init [--mode=isolated|overlay]` - Create environment
- `aptx shell` - Enter environment
- `aptx run <command>` - Run command in environment
- `aptx clean` - Remove environment
- `aptx global init` - Initialize global environment
- `aptx global install <package>` - Install global package
- `aptx global remove <package>` - Remove global package
- `aptx global clean` - Remove global environment

## About

aptx is inspired by modern package managers like `pixi` and `uv`, but designed specifically for the Ubuntu/APT ecosystem. While pixi excels at Python/Conda packages and uv handles Python dependencies, aptx fills the gap for APT packages, providing isolated environments, global package management, and seamless system integration that these tools don't offer for Ubuntu packages.

## Status: Work in Progress

- [x] Isolated environment creation and management
- [x] Overlay mode or isolated modes
- [x] Global package installation and system-wide access (isolated)
- [x] Package tracking and dependency management
- [ ] Environment import/export functionality
- [ ] Package version pinning and updates
- [ ] Easy installation

## Requirements

- Ubuntu/Debian system
- `fakechroot` package
