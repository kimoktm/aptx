#!/usr/bin/env bash
set -e

ROOT="$1"
[ -d "$ROOT" ] || { echo "Error: Directory '$ROOT' does not exist" >&2; exit 1; }
command -v fakechroot >/dev/null 2>&1 || { echo "Error: fakechroot is required" >&2; exit 1; }

ROOT_ABS=$(cd "$ROOT" && pwd)

# Check if this is overlay mode by looking for overlay scripts
OVERLAY_MODE=false
if [ -f "$ROOT_ABS/usr/local/bin/setup-overlay" ]; then
    OVERLAY_MODE=true
    echo "Detected safe overlay mode - setting up PATH for host binary access..."
    
    # SAFE OVERLAY MODE: No hardcoded symlinks - completely dynamic
    # This gives access to host tools without any system corruption risk
    
    # Create host directory references for PATH access
    # These are just directory structures, not mounts
    mkdir -p "$ROOT_ABS/host-bin" "$ROOT_ABS/host-usr" "$ROOT_ABS/host-lib"
    
    echo "Safe overlay mode prepared:"
    echo "  - Host binaries accessible via PATH (not hardcoded)"
    echo "  - No system corruption risk"
    echo "  - Completely dynamic and flexible"
fi

# Create a temporary file to store the package list before entering shell
TEMP_PACKAGES=$(mktemp)

# Get package list before entering shell
echo "Scanning packages before entering shell..."
echo "dpkg-query -W -f='\${Package}\n'" | sudo fakechroot chroot "$ROOT_ABS" 2>/dev/null | sort > "$TEMP_PACKAGES"

# Function to track new packages after shell exits
track_new_packages() {
    echo "Scanning packages after exiting shell..."
    
            # Get package list after exiting shell
        local after_packages=$(echo "dpkg-query -W -f='\${Package}\n'" | sudo fakechroot chroot "$ROOT_ABS" 2>/dev/null | sort)

        # Compare with before list to find new packages
        local new_packages=$(comm -23 <(echo "$after_packages") <(cat "$TEMP_PACKAGES"))

        # Filter out any packages that might be in an intermediate state
        local filtered_packages=""
        while IFS= read -r package; do
            if [ -n "$package" ]; then
                # Check if the package is fully installed and queryable
                local package_status=$(echo "dpkg-query -W -f='\${Status}' $package" | sudo fakechroot chroot "$ROOT_ABS" 2>/dev/null)
                if echo "$package_status" | grep -q "installed ok installed\|install ok installed"; then
                    filtered_packages="$filtered_packages$package"$'\n'
                else
                    echo "Skipping package not fully installed: $package (status: $package_status)"
                fi
            fi
        done <<< "$new_packages"
        new_packages="$filtered_packages"
    
    if [ -n "$new_packages" ]; then
        local new_count=$(echo "$new_packages" | grep -c .)
        echo "Found $new_count new packages installed during shell session..."
        
        # Track each new package
        while IFS= read -r package; do
            if [ -n "$package" ]; then
                # For new packages, mark as user if manually installed
                local package_type="dependency"  # Default to dependency
                local is_manual=$(echo "apt-mark showmanual | grep -q '^$package$' && echo 'yes' || echo 'no'" | sudo fakechroot chroot "$ROOT_ABS" 2>/dev/null)
                if [ "$is_manual" = "yes" ]; then
                    package_type="user"
                fi
                
                # Get package info with better error handling
                local package_info=$(echo "dpkg-query -W -f='{\"name\":\"\${Package}\",\"version\":\"\${Version}\",\"depends\":\"\${Depends}\"}' $package" | sudo fakechroot chroot "$ROOT_ABS" 2>/dev/null)
                
                # Validate that we got proper JSON-like output and it contains the expected fields
                if [ -n "$package_info" ] && echo "$package_info" | grep -q '"name":' && echo "$package_info" | grep -q '"version":'; then
                    # Parse the package info
                    local name=$(echo "$package_info" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                    local version=$(echo "$package_info" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
                    local depends=$(echo "$package_info" | grep -o '"depends":"[^"]*"' | cut -d'"' -f4)
                    
                    # Only add if we have valid package info
                    if [ -n "$name" ] && [ -n "$version" ] && [ "$name" != "null" ] && [ "$version" != "null" ] && [ "$name" != "" ] && [ "$version" != "" ]; then
                        # Add to aptx.toml
                        local aptx_toml="$ROOT_ABS/aptx.toml"
                        if [ -f "$aptx_toml" ]; then
                            cat >> "$aptx_toml" <<EOF

[[packages]]
name = "$name"
version = "$version"
type = "$package_type"
depends = "$depends"
EOF
                            echo "Tracked: $name ($version) as $package_type"
                        fi
                    else
                        echo "Skipping package with invalid info: $package (name='$name', version='$version')"
                    fi
                else
                    echo "Skipping package with malformed info: $package (got: '$package_info')"
                fi
            fi
        done <<< "$new_packages"
        
        echo "Package tracking updated!"
    else
        echo "No new packages found."
    fi
    
    # Clean up temporary file
    rm -f "$TEMP_PACKAGES"
    
    # Fix ownership of newly installed packages so .aptx directory can be deleted without sudo
    if [ -n "$new_packages" ]; then
        echo "Fixing ownership of newly installed packages..."
        if [ -n "$SUDO_USER" ]; then
            # If run with sudo, use the original user
            OWNER="$SUDO_USER"
        else
            # Otherwise use current user
            OWNER="$USER"
        fi
        
        # Fix ownership of the entire environment to ensure all files can be deleted
        sudo chown -R "$OWNER:$OWNER" "$ROOT_ABS" 2>/dev/null || true
        echo "Ownership fixed for user: $OWNER"
    fi
}

# Use sudo if available, otherwise try fakeroot
if command -v sudo >/dev/null 2>&1; then
    # Run the chroot command and capture its exit code
    if sudo fakechroot chroot "$ROOT_ABS" /bin/bash -c "
        export TERM=\$TERM COLUMNS=\$COLUMNS LINES=\$LINES HOME=/root
        export PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
        export DEBIAN_FRONTEND=noninteractive
        cd /root 2>/dev/null || cd /
        
        # Add host directories to PATH if in overlay mode
        if [ -d /host-bin ] && [ -d /host-usr ]; then
            # Run the safe overlay setup script
            if [ -f /usr/local/bin/setup-overlay ]; then
                source /usr/local/bin/setup-overlay
            fi
            echo 'Safe overlay mode: Host binaries available as PATH fallback'
        fi
        
        # Run apt update once if not done before
        # TODO: Fix APT permissions to eliminate permission warnings (create _apt user, fix directory permissions)
        if [ ! -f /var/lib/apt/lists/.updated ]; then
            echo 'Updating package lists...'
            apt update 2>/dev/null && touch /var/lib/apt/lists/.updated || echo 'Update failed - will retry later'
        fi
        
        exec /bin/bash --login
    "; then
        exit_code=$?
    else
        exit_code=$?
    fi
else
    # Run the chroot command and capture its exit code
    if fakechroot fakeroot chroot "$ROOT_ABS" /bin/bash -c "
        export TERM=\$TERM COLUMNS=\$COLUMNS LINES=\$LINES HOME=/root
        export PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
        export DEBIAN_FRONTEND=noninteractive
        cd /root 2>/dev/null || cd /
        
        # Add host directories to PATH if in overlay mode
        if [ -d /host-bin ] && [ -d /host-usr ]; then
            # Run the safe overlay setup script
            if [ -f /usr/local/bin/setup-overlay ]; then
                source /usr/local/bin/setup-overlay
            fi
            echo 'Safe overlay mode: Host binaries available as PATH fallback'
        fi
        
        # Run apt update once if not done before
        # TODO: Fix APT permissions to eliminate permission warnings (create _apt user, fix directory permissions)
        if [ ! -f /var/lib/apt/lists/.updated ]; then
            echo 'Updating package lists...'
            apt update 2>/dev/null && touch /var/lib/apt/lists/.updated || echo 'Update failed - will retry later'
        fi
        
        exec /bin/bash --login
    "; then
        exit_code=$?
    else
        exit_code=$?
    fi
fi

# Always track packages after shell exits
track_new_packages

# Cleanup overlay mode if active (check if host directories exist)
if [ -d "$ROOT_ABS/host-bin" ] || [ -d "$ROOT_ABS/host-usr" ]; then
    echo "Cleaning up safe overlay mode..."
    # Call the cleanup script inside the chroot
    if [ -f "$ROOT_ABS/usr/local/bin/cleanup-overlay" ]; then
        sudo fakechroot chroot "$ROOT_ABS" /usr/local/bin/cleanup-overlay 2>/dev/null || true
    fi
    echo "Safe overlay cleanup complete"
fi

# Exit with the same code as the chroot command
exit $exit_code
