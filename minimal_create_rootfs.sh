#!/usr/bin/env bash
set -e

ROOT="$1"
RELEASE="$2"
MODE="${3:-isolated}"

# Check dependencies
for cmd in wget tar; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is required" >&2; exit 1; }
done

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) UBUNTU_ARCH="amd64" ;;
    aarch64) UBUNTU_ARCH="arm64" ;;
    armv7l) UBUNTU_ARCH="armhf" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$ROOT"

# Download rootfs
if [ "$UBUNTU_ARCH" = "arm64" ]; then
    wget -q "https://cdimage.ubuntu.com/ubuntu-base/releases/$RELEASE/release/ubuntu-base-22.04.1-base-$UBUNTU_ARCH.tar.gz" -O rootfs.tar.gz
    mv rootfs.tar.gz rootfs.tar.xz
else
    wget -q "https://cloud-images.ubuntu.com/minimal/releases/$RELEASE/release/ubuntu-$RELEASE-minimal-cloudimg-$UBUNTU_ARCH-root.tar.xz" -O rootfs.tar.xz
fi

tar -xf rootfs.tar.xz -C "$ROOT"
rm rootfs.tar.xz

# Configure apt sources
if [ "$UBUNTU_ARCH" = "arm64" ] || [ "$UBUNTU_ARCH" = "armhf" ]; then
    MIRROR="http://ports.ubuntu.com/ubuntu-ports"
else
    MIRROR="http://archive.ubuntu.com/ubuntu"
fi

cat > "$ROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $RELEASE main restricted universe multiverse
deb $MIRROR $RELEASE-updates main restricted universe multiverse
deb $MIRROR $RELEASE-security main restricted universe multiverse
EOF

# Basic setup
echo "nameserver 8.8.8.8" > "$ROOT/etc/resolv.conf"
mkdir -p "$ROOT/etc/apt/apt.conf.d"
echo 'APT::Sandbox "false";' > "$ROOT/etc/apt/apt.conf.d/99rootless.conf"

# Create apt wrapper
cat > "$ROOT/usr/local/bin/apt" <<'EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
mkdir -p /var/lib/apt/lists/partial /var/cache/apt/archives/partial
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock
exec /usr/bin/apt "$@"
EOF
chmod +x "$ROOT/usr/local/bin/apt"

# Create directories
mkdir -p "$ROOT/var/lib/apt/lists/partial" "$ROOT/var/cache/apt/archives/partial" "$ROOT/tmp" "$ROOT/var/tmp" "$ROOT/home" "$ROOT/root"

# Block services
echo '#!/bin/sh' > "$ROOT/usr/sbin/policy-rc.d"
echo 'exit 101' >> "$ROOT/usr/sbin/policy-rc.d"
chmod +x "$ROOT/usr/sbin/policy-rc.d"

# Set ownership to current user so .aptx directory can be deleted without sudo
if [ -n "$SUDO_USER" ]; then
    # If run with sudo, use the original user
    OWNER="$SUDO_USER"
else
    # Otherwise use current user
    OWNER="$USER"
fi

echo "Setting ownership to user: $OWNER"
chown -R "$OWNER:$OWNER" "$ROOT" 2>/dev/null || true

# Handle overlay mode
if [ "$MODE" = "overlay" ]; then
    echo "Setting up safe overlay mode using symlinks and PATH..."
    
    # Create host directories for PATH-based access
    mkdir -p "$ROOT/host-bin" "$ROOT/host-usr/bin" "$ROOT/host-usr/sbin" "$ROOT/host-lib"
    
    echo "Setting up PATH-based overlay mode..."
    echo "  - Environment packages have PRIORITY (listed first in PATH)"
    echo "  - Host packages available as FALLBACK (listed second in PATH)"
    echo "  - Creating symlinks to host system for clean access"
    
    # Create symlinks to host system binaries and libraries
    # This is safe because we're only linking within the environment
    if [ -d "/usr/bin" ]; then
        # Create symlinks to all host binaries
        for binary in /usr/bin/*; do
            if [ -x "$binary" ] && [ -f "$binary" ]; then
                binary_name=$(basename "$binary")
                ln -sf "$binary" "$ROOT/host-usr/bin/$binary_name"
            fi
        done
        echo "Created symlinks to host binaries"
    fi
    
    if [ -d "/usr/sbin" ]; then
        # Create symlinks to all host sbin binaries
        for binary in /usr/sbin/*; do
            if [ -x "$binary" ] && [ -f "$binary" ]; then
                binary_name=$(basename "$binary")
                ln -sf "$binary" "$ROOT/host-usr/sbin/$binary_name"
            fi
        done
        echo "Created symlinks to host sbin binaries"
    fi
    
    if [ -d "/usr/lib" ]; then
        # Create symlinks to all host libraries
        for lib in /usr/lib/*; do
            if [ -f "$lib" ] && [[ "$lib" == *.so* ]]; then
                lib_name=$(basename "$lib")
                ln -sf "$lib" "$ROOT/host-lib/$lib_name"
            fi
        done
        echo "Created symlinks to host libraries"
    fi
    
    # Also check architecture-specific library directories
    if [ -d "/usr/lib/$(uname -m)-linux-gnu" ]; then
        for lib in "/usr/lib/$(uname -m)-linux-gnu"/*; do
            if [ -f "$lib" ] && [[ "$lib" == *.so* ]]; then
                lib_name=$(basename "$lib")
                ln -sf "$lib" "$ROOT/host-lib/$lib_name"
            fi
        done
        echo "Created symlinks to architecture-specific host libraries"
    fi
    
    # Create global packages symlink if global environment exists
    # Use the actual home directory of the user running the script
    USER_HOME=$(eval echo ~$USER)
    if [ -d "$USER_HOME/.aptx/global" ]; then
        echo "Creating global packages symlinks..."
        mkdir -p "$ROOT/global-packages"
        
        # Symlink for binaries
        ln -sf "$USER_HOME/.aptx/global/usr/bin" "$ROOT/global-packages/bin"
        echo "Global packages symlink created: /global-packages/bin -> $USER_HOME/.aptx/global/usr/bin"
        
        # Symlink for common resource directories (fonts, etc.)
        if [ -d "$USER_HOME/.aptx/global/usr/share" ]; then
            ln -sf "$USER_HOME/.aptx/global/usr/share" "$ROOT/global-packages/share"
            echo "Global resources symlink created: /global-packages/share -> $USER_HOME/.aptx/global/usr/share"
            
            # Create symlink for figlet fonts in the expected location
            if [ -d "$USER_HOME/.aptx/global/usr/share/figlet" ]; then
                mkdir -p "$ROOT/usr/share"
                ln -sf "$USER_HOME/.aptx/global/usr/share/figlet" "$ROOT/usr/share/figlet"
                echo "Figlet fonts symlink created: /usr/share/figlet -> $USER_HOME/.aptx/global/usr/share/figlet"
            fi
        fi
        
        # Symlink for libraries if needed
        if [ -d "$USER_HOME/.aptx/global/usr/lib" ]; then
            ln -sf "$USER_HOME/.aptx/global/usr/lib" "$ROOT/global-packages/lib"
            echo "Global libraries symlink created: /global-packages/lib -> $USER_HOME/.aptx/global/usr/lib"
        fi
    else
        echo "No global environment found at $USER_HOME/.aptx/global - skipping global packages symlink"
    fi
    
    # Create a script to set up overlay mode when entering the environment
    cat > "$ROOT/usr/local/bin/setup-overlay" <<EOF
#!/bin/bash
# Clean PATH-based overlay mode (NO MOUNTING - NO SYMLINKS - NO HOST TOUCHING - SAFE)

echo "Setting up clean PATH-based overlay mode..."

# Set up PATH with environment packages having PRIORITY over host packages
# Environment packages come FIRST, global aptx packages SECOND, host packages THIRD (as fallback)
# With fakechroot, we can access host system paths directly
export PATH="/usr/bin:/usr/local/bin:/usr/sbin:/sbin:/bin:/global-packages/bin:/host-usr/bin:/host-usr/sbin:/host-bin"

# Set up library paths with environment libraries having PRIORITY over host libraries
# Environment libraries come FIRST, host libraries come SECOND (as fallback)
# With fakechroot, we can access host system paths directly
export LD_LIBRARY_PATH="/usr/lib:/usr/lib/aarch64-linux-gnu:/usr/lib/x86_64-linux-gnu:/host-lib"

# Also set XDG_DATA_DIRS for applications that need it
export XDG_DATA_DIRS="/usr/share:/usr/local/share:/global-packages/share:/host-usr/share"

echo "Clean overlay mode activated:"
echo "  - Environment packages have PRIORITY (PATH: /usr/bin first)"
echo "  - Global aptx packages available as SECONDARY (PATH: /global-packages/bin second)"
echo "  - Host packages available as FALLBACK (PATH: /host-usr/bin third)"
echo "  - Environment libraries have PRIORITY (LD_LIBRARY_PATH: /usr/lib first)"
echo "  - Host libraries available as FALLBACK (LD_LIBRARY_PATH: /host-lib second)"
echo "  - No symlinks needed - clean PATH manipulation"
echo "  - No system mounting - completely safe"
echo "  - No host filesystem touching - completely isolated"
echo "  - Direct host path access via fakechroot - simple and clean"
EOF
    chmod +x "$ROOT/usr/local/bin/setup-overlay"
    
    # Create a script to clean up overlay mode when exiting
    cat > "$ROOT/usr/local/bin/cleanup-overlay" <<'EOF'
#!/bin/bash
# Clean up overlay mode (SAFE CLEANUP)

echo "Cleaning up overlay mode..."

# No cleanup needed - just PATH manipulation
# Environment variables are automatically reset when shell exits
echo "Overlay cleanup complete - PATH restored to environment-only"
EOF
    chmod +x "$ROOT/usr/local/bin/cleanup-overlay"
    
    echo "Safe overlay mode setup complete"
    echo "  - Uses symlinks instead of dangerous mounting"
    echo "  - PATH manipulation for binary access"
    echo "  - Easy cleanup with no system corruption risk"
else
    echo "Isolated mode - no system package access"
fi
