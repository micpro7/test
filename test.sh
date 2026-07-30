#!/bin/sh
# Safe-mode: Exit immediately if any command fails
set -e

echo "========================================================"
echo " ⚡ HOMEBRIDGE UXC MASTER INITIALIZATION ENGINE v2 ⚡"
echo "========================================================"
printf '\n\n\n'


# ==============================================================================
# PART 1: MASTER CONFIGURATION VARIABLES (Central Variables Hub)
# ==============================================================================

# ==============================================================================
# GITHUB DOWNLOAD CONFIGURATION
# ==============================================================================

BUNDLE_URL="https://github.com/micpro7/openwrt-uxc-homebridge/releases/latest/download/homebridge-arm64.tar.gz"

# ==============================================================================
# CONFIGURATION VARIABLES (Edit these to tune your deployment)
# ==============================================================================

CONTAINER_NAME="homebridge"

# Physical SSD mount point
TARGET_MOUNT="/mnt/X6"


# Derived Variables
ARCHIVE="$TARGET_MOUNT/homebridge.tar.gz"

BUNDLE_PATH="$TARGET_MOUNT/UXC/$CONTAINER_NAME/bundle"

# NEW:
# Persistent Homebridge data now maps directly to /homebridge
PERSISTENT_DATA_SOURCE="$TARGET_MOUNT/UXC/$CONTAINER_NAME/homebridge"

# ==============================================================================
# ENVIRONMENT VARIABLES & PERFORMANCE TUNING
# ==============================================================================

TIMEZONE="Europe/London"

# Host Avahi handles mDNS.
# Kept for compatibility with Homebridge environment.
MDNS_NET_INTERFACE="br-lan"

# Node memory tuning
NODE_MEMORY_LIMIT="256"

# Libuv worker threads
THREAD_POOL_SIZE="4"

# Homebridge UI binding
BIND_IP="0.0.0.0"

# Security Parameters
NO_NEW_PRIVILEGES=false


# ==============================================================================


# ==============================================================================
# PHASE 0.5: CREATE CENTRAL VARIABLE ENVIRONMENT FILE
# ==============================================================================
echo "📝 Creating persistent Homebridge variable map..."

cat > /etc/homebridge.conf << EOF
CONTAINER_NAME="$CONTAINER_NAME"

TARGET_MOUNT="$TARGET_MOUNT"

BUNDLE_PATH="$BUNDLE_PATH"

PERSISTENT_DATA_SOURCE="$PERSISTENT_DATA_SOURCE"

TIMEZONE="$TIMEZONE"

MDNS_NET_INTERFACE="$MDNS_NET_INTERFACE"

NODE_MEMORY_LIMIT="$NODE_MEMORY_LIMIT"

THREAD_POOL_SIZE="$THREAD_POOL_SIZE"

BIND_IP="$BIND_IP"

NO_NEW_PRIVILEGES="$NO_NEW_PRIVILEGES"

EOF

chmod 600 /etc/homebridge.conf

echo "✅ Central variable map saved to /etc/homebridge.conf"

echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==========================================
# Phase 1: Environment & Dependency Check
# ==========================================
echo "🔄 [Phase 1] Syncing OpenWrt core infrastructure dependencies..."



# Verify SSD mount before writing
echo "🔍 Verifying target storage..."


if ! grep -qs " $TARGET_MOUNT " /proc/mounts; then

    echo "❌ Error: $TARGET_MOUNT is not mounted. Aborting to avoid RAM writes." >&2

    exit 1

fi


echo "✅ $TARGET_MOUNT verified successfully."



apk update


# Keep Avahi installed
# Homebridge discovery remains compatible with host mDNS setup

apk add --no-cache \
    uxc \
    procd-ujail \
    kmod-veth \
    jq \
    avahi \
    avahi-tools



echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==========================================
# Phase 2: Runtime Workspace Purge
# ==========================================
echo "🧹 [Phase 2] Clearing out stale runtime structures..."



uxc kill "$CONTAINER_NAME" 2>/dev/null || true

uxc delete "$CONTAINER_NAME" --force 2>/dev/null || true



echo "[i] Removing previous container bundle..."

rm -rf "$BUNDLE_PATH"



echo "========(+) DONE ✅ (+)========"
printf '\n\n\n'



# ==========================================
# Phase 3: Structural Path Assembly
# ==========================================
echo "📂 [Phase 3] Constructing host storage target directories..."

echo "[i] Creating bundle directory..."

mkdir -p "$BUNDLE_PATH"



echo "[i] Creating persistent Homebridge storage..."

mkdir -p \
"$PERSISTENT_DATA_SOURCE/accessories" \
"$PERSISTENT_DATA_SOURCE/backups" \
"$PERSISTENT_DATA_SOURCE/logs" \
"$PERSISTENT_DATA_SOURCE/persist" \
"$PERSISTENT_DATA_SOURCE/node_modules"



sync



echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==========================================
# Phase 4: Bundle Fetch & Verification
# ==========================================
echo "📥 [Phase 4] Pulling production blueprint package from GitHub..."



if ! wget -q --show-progress -O "$ARCHIVE" "$BUNDLE_URL"; then

    echo "❌ Error: Failed to download Homebridge bundle." >&2

    exit 1

fi
printf '\n\n\n'



echo "📦 Extracting package payload onto $TARGET_MOUNT storage..."



if ! tar -xpf "$ARCHIVE" -C "$BUNDLE_PATH"; then

    echo "❌ Error: Failed to extract Homebridge bundle." >&2

    rm -f "$ARCHIVE"

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



sync


rm -f "$ARCHIVE"
printf '\n\n\n'



# Validate bundle structure


if [ ! -f "$BUNDLE_PATH/config.json" ] || [ ! -d "$BUNDLE_PATH/rootfs" ]; then

    echo "❌ [ERROR] Missing critical bundle files. Halting deployment." >&2

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



# Validate JSON


if ! jq empty "$BUNDLE_PATH/config.json" >/dev/null 2>&1; then

    echo "❌ [ERROR] config.json is invalid or corrupt." >&2

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



echo "   config.json validated  ✅"

echo "   rootfs engine verified ✅"

echo "🚀 OCI application bundle authenticated."



echo "========(+) DONE ✅ (+)========"
printf '\n\n\n'

# ==========================================
# Phase 5: Dynamic Variable Injection (JQ Splits)
# ==========================================

echo "📝 [Phase 5] Injecting Homebridge runtime matrix via individual JQ splits..."



# ==============================================================================
# Split 1: Update Persistent Storage Path Mount Source
# Official Homebridge container layout: /homebridge
# ==============================================================================
jq --arg src "$PERSISTENT_DATA_SOURCE" \
'.mounts = (.mounts | map(if .destination == "/homebridge" then .source = $src else . end))' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Persistent Homebridge storage bound to: $PERSISTENT_DATA_SOURCE ✅"





# ==============================================================================
# Split 2: Update Timezone
# ==============================================================================
jq --arg tz "TZ=$TIMEZONE" \
'.process.env = (.process.env | map(if startswith("TZ=") then $tz else . end))' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"
echo "   ↳ Timezone assigned to: $TIMEZONE ✅"





# ==============================================================================
# Split 3: Homebridge Storage Path
#
# Critical change:
# Homebridge data is now permanently stored in /homebridge
# ==============================================================================
jq \
'.process.env += ["HOMEBRIDGE_STORAGE_PATH=/homebridge"]' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Homebridge storage path forced to /homebridge ✅"


# ==============================================================================
# Split 4: Enable Config UI X
# ==============================================================================
jq \
'.process.env += ["HOMEBRIDGE_CONFIG_UI=1"]' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Homebridge Config UI enabled ✅"


# ==============================================================================
# Split 5: Update Node.js Heap Memory
# ==============================================================================
jq --arg node_opt "NODE_OPTIONS=--max-old-space-size=$NODE_MEMORY_LIMIT" \
'.process.env = (.process.env | map(if startswith("NODE_OPTIONS=") then $node_opt else . end))' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Node.js heap limit set to ${NODE_MEMORY_LIMIT}MB ✅"


# ==============================================================================
# Split 6: Update Libuv Thread Pool
# ==============================================================================
jq --arg threads "UV_THREADPOOL_SIZE=$THREAD_POOL_SIZE" \
'.process.env = (.process.env | map(if startswith("UV_THREADPOOL_SIZE=") then $threads else . end))' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Libuv worker threads balanced at: $THREAD_POOL_SIZE ✅"



# ==============================================================================
# Split 7: Update Homebridge Network Binding
# ==============================================================================
jq --arg ip "HOMEBRIDGE_IP=$BIND_IP" \
'.process.env = (.process.env | map(if startswith("HOMEBRIDGE_IP=") then $ip else . end))' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Network bind target set to: $BIND_IP ✅"



# ==============================================================================
# Split 8: Kernel Security Boundary
# ==============================================================================
jq --argjson nnp "$NO_NEW_PRIVILEGES" \
'.process.noNewPrivileges = $nnp' \
"$BUNDLE_PATH/config.json" > "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"

echo "   ↳ Kernel privilege escalation guard: $NO_NEW_PRIVILEGES ✅"





printf '\n\n\n'


echo "⚙️ UXC Homebridge blueprint compiled permanently onto SSD."

echo "========(+) DONE ✅ (+)========"
printf '\n\n\n'


# ==========================================
# Phase 6: Container Registration & Ignition
# ==========================================
echo "🏗️ [Phase 6] Registering container blueprint with UXC engine..."



uxc create "$CONTAINER_NAME" \
    --bundle "$BUNDLE_PATH" \
    --mounts "$TARGET_MOUNT"



printf '\n\n\n'


echo "⏳ Holding engine execution for stabilization (3s)..."

sleep 3

printf '\n\n\n'

echo "🏁 Spawning Homebridge runtime daemon..."

uxc start "$CONTAINER_NAME"
printf '\n\n\n'


echo "✨ Active container framework status verified:"
uxc list

echo "========(+) DONE ✅ (+)========"
printf '\n\n\n'
