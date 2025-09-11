# aptx

**Goal**: Provide isolated, reproducible Ubuntu environments for APT packages, completely separated from system packages with global package access, ensuring consistent builds across different systems.

aptx is inspired by modern package managers like `pixi` and `uv`, but designed specifically for the Ubuntu/APT ecosystem. While pixi excels at Python/Conda packages and uv handles Python dependencies, aptx fills the gap for APT packages, providing isolated environments, global package management, and seamless system integration that these tools don't offer for Ubuntu packages.

**Note**: This project is a work in progress (WIP).

## Quick Start

```bash
# Initialize environment
aptx init

# Enter environment
aptx shell

# Install packages (doesn't affect your system)
apt install <apt_package>

# Exit environment
exit
```

## What It Does

aptx creates **isolated** Ubuntu environments where you can:
- Install packages with `apt` without affecting your system
- Run any commands in isolation
- Have consistent environments across different machines

## Examples

### Basic Environment Usage
```bash
# Create environment
aptx init

# Enter and install packages
aptx install gcc make cmake
aptx shell
gcc --version
exit

# Your system remains unchanged!
```

### Running Commands Without Entering Shell
```bash
# Run single commands
aptx run apt install gcc # or just aptx install gcc
aptx run gcc --version
aptx run ls /usr/bin/gcc

# Run multiple commands
aptx run "apt update && apt install -y build-essential"
```

### Global Packages
```bash
# Install globally (available everywhere)
aptx global init
aptx global install htop tree

# Use from anywhere
htop
tree

# Also works in local environments
cd my_project
aptx init --mode=overlay
htop  # Available automatically!
```

## Modes

**Isolated** (default): Completely isolated environment
```bash
aptx init
```

**Overlay**: Can access system packages (read-only)
```bash
aptx init --mode=overlay
```

## Commands

- `aptx init [--mode=isolated|overlay]` - Create environment
- `aptx shell` - Enter environment
- `aptx run <command>` - Run command in environment
- `aptx clean` - Remove environment
- `aptx global init` - Initialize global environment
- `aptx global install <package>` - Install global package
- `aptx global remove <package>` - Remove global package
- `aptx global clean` - Remove global environment

## Status: Work in Progress

- [x] Isolated environment creation and management
- [x] Overlay mode or isolated modes
- [x] Global package installation and system-wide access (isolated)
- [x] Package tracking and dependency management
- [ ] Expose the installed packages (user, or dependecy) in a toml file
- [ ] Environment import/export functionality
- [ ] Package version pinning and updates
- [ ] Easy installation

## Requirements

- Ubuntu/Debian system
- `fakechroot` package
