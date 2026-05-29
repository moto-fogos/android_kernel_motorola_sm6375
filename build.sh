#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 WakacaW Project
#
# Kernel Build Script — WakacaW
# Device: fogos (Moto G34/G45 5G)

# ──────────────────────────────────────────────
#  BUILD ENVIRONMENT
# ──────────────────────────────────────────────
export KBUILD_BUILD_USER=byben
export KBUILD_BUILD_HOST=wkcw
export LLVM=1
export LLVM_IAS=1

# ──────────────────────────────────────────────
#  PATHS
# ──────────────────────────────────────────────
TC_DIR="$HOME/toolchains/clang"
TC_REPO="https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone"
AK3_DIR="AnyKernel3"
AK3_REPO="https://github.com/heybyben/AnyKernel3-hey"
AK3_BRANCH="master"
OUTPUT_DIR="out"
ZIPNAME="WakacaW-fogos-$(TZ=UTC date '+%Y%m%d-%H%M').zip"

export PATH="$TC_DIR/bin:$PATH"
export modpath="${AK3_DIR}/modules/vendor/lib/modules"

# ──────────────────────────────────────────────
#  DEFCONFIG
# ──────────────────────────────────────────────
DEFCONFIG="vendor/wakacaw_defconfig"

# ──────────────────────────────────────────────
#  TELEGRAM CONFIG (.env)
# ──────────────────────────────────────────────
ENV_FILE="$(dirname "$(realpath "$0")")/.env"

load_tg_config() {
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        log_info "Loaded Telegram config from .env"
        return
    fi

    log_warn ".env not found, setting up Telegram config..."
    echo ""

    read -rp "  Enter Bot Token   : " input_token
    read -rp "  Enter Chat ID     : " input_chat_id

    [ -z "$input_token" ]   && die "Bot Token cannot be empty!"
    [ -z "$input_chat_id" ] && die "Chat ID cannot be empty!"

    cat > "$ENV_FILE" <<EOF
TG_TOKEN="${input_token}"
TG_CHAT_ID="${input_chat_id}"
EOF
    chmod 600 "$ENV_FILE"
    log_ok "Config saved to .env (mode 600)"

    TG_TOKEN="$input_token"
    TG_CHAT_ID="$input_chat_id"
}

TG_TOKEN=""
TG_CHAT_ID=""

# ──────────────────────────────────────────────
#  COLORS & LOGGING
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}   $*"; }
log_step()  { echo -e "\n${BOLD}${CYAN}>>> $* ${NC}"; }
die()       { log_err "$*"; exit 1; }

# ──────────────────────────────────────────────
#  CLONE TOOLCHAIN
# ──────────────────────────────────────────────
clone_toolchain() {
    if [ -d "$TC_DIR" ]; then
        log_info "Toolchain already exists, skipping clone."
        return
    fi
    log_step "Toolchain not found, cloning..."
    git clone --depth=1 "$TC_REPO" "$TC_DIR" \
        || die "Failed to clone toolchain!"
    log_ok "Toolchain cloned successfully."
}

# ──────────────────────────────────────────────
#  CLONE ANYKERNEL3
# ──────────────────────────────────────────────
clone_anykernel3() {
    if [ -d "$AK3_DIR" ]; then
        log_info "AnyKernel3 already exists, checking out branch $AK3_BRANCH..."
        git -C "$AK3_DIR" checkout "$AK3_BRANCH" &>/dev/null \
            || log_warn "Failed to checkout branch $AK3_BRANCH."
        return
    fi
    log_step "AnyKernel3 not found, cloning..."
    git clone -q --depth=1 -b "$AK3_BRANCH" "$AK3_REPO" "$AK3_DIR" \
        || die "Failed to clone AnyKernel3!"
    log_ok "AnyKernel3 cloned successfully."
}

# ──────────────────────────────────────────────
#  CLEAN
# ──────────────────────────────────────────────
do_clean() {
    log_step "Clean build..."
    make O="$OUTPUT_DIR" clean
    rm -rf "$OUTPUT_DIR"
    log_ok "Clean done."
}

# ──────────────────────────────────────────────
#  BUILD KERNEL
# ──────────────────────────────────────────────
build_kernel() {
    log_step "Generating defconfig: $DEFCONFIG"
    mkdir -p "$OUTPUT_DIR"

    make O="$OUTPUT_DIR" ARCH=arm64 "$DEFCONFIG" -j"$(nproc)" \
        || die "Defconfig failed!"

    log_step "Building kernel with $(nproc) jobs..."
    local START END ELAPSED
    START=$(date +%s)

    make O="$OUTPUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        -j"$(nproc)" \
        || die "Build FAILED!"

    END=$(date +%s)
    ELAPSED=$((END - START))
    printf "${GREEN}[OK]${NC}    Kernel built in %02dh %02dm %02ds\n" \
        $((ELAPSED / 3600)) $(((ELAPSED % 3600) / 60)) $((ELAPSED % 60))

    # Save elapsed for use in Telegram
    BUILD_TIME=$(printf "%02dh %02dm %02ds" \
        $((ELAPSED / 3600)) $(((ELAPSED % 3600) / 60)) $((ELAPSED % 60)))

    [ -f "$OUTPUT_DIR/arch/arm64/boot/Image" ] \
        || die "Image not found after build!"
}

# ──────────────────────────────────────────────
#  INSTALL MODULES
# ──────────────────────────────────────────────
install_modules() {
    log_step "Installing modules..."

    make O="$OUTPUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        -j"$(nproc)" \
        INSTALL_MOD_PATH=modules \
        INSTALL_MOD_STRIP=1 \
        modules_install \
        || die "Module install failed!"

    local kver
    kver=$(make kernelversion)
    mkdir -p "$modpath"

    cp $(find "$OUTPUT_DIR/modules/lib/modules/${kver}"* -name '*.ko') "$modpath/"
    cp "$OUTPUT_DIR/modules/lib/modules/${kver}"*/modules.{alias,dep,softdep} "$modpath/"
    cp "$OUTPUT_DIR/modules/lib/modules/${kver}"*/modules.order "$modpath/modules.load"

    sed -i 's@\(\S*/\)\([^: ]*\.ko\)@/vendor/lib/modules/\2@g' "$modpath/modules.dep"
    sed -i 's/.*\///; s/\.ko$//' "$modpath/modules.load"

    log_ok "Modules installed."
}

# ──────────────────────────────────────────────
#  PACKAGE ZIP
# ──────────────────────────────────────────────
package_zip() {
    log_step "Packaging AnyKernel3..."

    rm -rf "${AK3_DIR}"/{Image,dtb,dtbo.img} "${AK3_DIR}"/*.zip
    rm -rf "$modpath"/*

    cp "$OUTPUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/"
    cp "$OUTPUT_DIR/arch/arm64/boot/dtb.img"  "$AK3_DIR/dtb"      2>/dev/null && log_info "DTB copied."
    cp "$OUTPUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/dtbo.img" 2>/dev/null && log_info "DTBO copied."

    install_modules

    cd "$AK3_DIR"
    zip -r9 "../$ZIPNAME" . \
        -x "*.git*" -x "*.github*" -x "README*" -x "*.zip" -x "*placeholder"
    cd ..

    [ -f "$ZIPNAME" ] \
        && log_ok "ZIP ready: $ZIPNAME ($(du -sh "$ZIPNAME" | cut -f1))" \
        || die "Failed to create ZIP!"
}

# ──────────────────────────────────────────────
#  TELEGRAM
# ──────────────────────────────────────────────
tg_send_msg() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode="Markdown" \
        -d text="$msg" \
        > /dev/null
}

tg_send_file() {
    local file="$1"
    local caption="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F parse_mode="Markdown" \
        -F caption="$caption" \
        -F document=@"$file" \
        > /dev/null
}

do_release() {
    load_tg_config
    [ -z "$TG_TOKEN" ]   && die "TG_TOKEN is empty!"
    [ -z "$TG_CHAT_ID" ] && die "TG_CHAT_ID is empty!"
    [ -f "$ZIPNAME" ]    || die "ZIP not found: $ZIPNAME"

    local kver
    kver=$(make kernelversion 2>/dev/null)
    local zipsize
    zipsize=$(du -sh "$ZIPNAME" | cut -f1)
    local date_str
    date_str=$(TZ=UTC date '+%Y-%m-%d %H:%M UTC')

    log_step "Sending release to Telegram..."

    local sha1
    sha1=$(sha1sum "$ZIPNAME" | cut -d' ' -f1)

    tg_send_file "$ZIPNAME" "*WakacaW | fogos* | Build took ${BUILD_TIME:-N/A}. | Kernel: \`${kver}\` | SHA1: \`${sha1}\`"

    log_ok "Released to Telegram!"
}

# ──────────────────────────────────────────────
#  MAIN
# ──────────────────────────────────────────────
main() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════╗"
    echo "║       WAKACAW KERNEL BUILDER         ║"
    echo "║       fogos | Moto G34/G45 5G        ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"

    local CLEAN=false
    local RELEASE=false

    for arg in "$@"; do
        case "$arg" in
            -c|--clean)   CLEAN=true ;;
            -r|--release) RELEASE=true ;;
        esac
    done
    load_tg_config
    clone_toolchain
    clone_anykernel3
    $CLEAN && do_clean
    build_kernel
    package_zip
    $RELEASE && do_release

    echo -e "\n${BOLD}${GREEN}✓ BUILD DONE!${NC}"
    echo -e "  ZIP: ${CYAN}$(pwd)/$ZIPNAME${NC}\n"
}

main "$@"
