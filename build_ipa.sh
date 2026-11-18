#!/bin/bash
# =============================================================================
# build_ipa.sh — Build the modified Bootmine-roothide as an IPA/TIPA on macOS
# -----------------------------------------------------------------------------
# This repository cannot be compiled on Linux (it needs Xcode, the iOS SDK,
# Theos, ldid and libarchive). Run this script on a macOS machine.
#
# Usage:
#   cd Bootmine-roothide
#   chmod +x build_ipa.sh
#   ./build_ipa.sh
#
# Output:
#   ./Application/Bootmine-roothide-<version>.ipa
#   ./Application/Bootmine-roothide-<version>.tipa   (identical, for TrollStore)
# =============================================================================
set -e

BASEDIR="$(pwd)"
echo "[*] BASEDIR = $BASEDIR"

# ---- 1. Homebrew dependencies ------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "[!] Homebrew not found. Install it first:" \
         "https://brew.sh" && exit 1
fi
brew install make libarchive openssl@3
# GNU make is required; put it first on PATH.
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
export GMAKE="$(brew --prefix make)/bin/gmake"

# ---- 2. Procursus toolchain (ldid, coreutils, sed, make) ---------------------
# If you already have these via Procursus on PATH, skip. Otherwise install via
# the procursus bootstrap, e.g.:
#   curl -L https://procursus.team/static/bootstrap/darwin/arm64/procursus.tar.zst ...
# The GitHub Actions workflow uses dhinakg/procursus-action with:
#   packages: ldid findutils sed coreutils make
command -v ldid  >/dev/null 2>&1 || { echo "[!] ldid missing (install via Procursus)"; exit 1; }

# ---- 3. Submodules -----------------------------------------------------------
echo "[*] Fetching submodules ..."
git submodule update --init --recursive

# ---- 4. Theos + iOS 16.5 SDK -------------------------------------------------
export THEOS="$BASEDIR/theos"
if [ ! -d "$THEOS" ]; then
    echo "[*] Installing Theos ..."
    curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos -o install-theos.sh
    # The roothide fork ships its own SDK logic; avoid the online SDK downloader.
    gsed -E "/^\s*get_theos\s*$/,+1 s/^(\s*)(get_sdks)\s*$/\1mkdir -p \${THEOS}\/sdks\n\1touch \${THEOS}\/sdks\/sdk\n\1\2/g" -i install-theos.sh
    bash install-theos.sh
    echo "[*] Installing iOS 16.5 SDK ..."
    curl -L https://github.com/theos/sdks/releases/latest/download/iPhoneOS16.5.sdk.tar.xz -o "$THEOS/sdks/iPhoneOS16.5.sdk.tar.xz"
    gunzip "$THEOS/sdks/iPhoneOS16.5.sdk.tar.xz"
    tar -xf "$THEOS/sdks/iPhoneOS16.5.sdk.tar" -C "$THEOS/sdks"
    rm -f "$THEOS/sdks/iPhoneOS16.5.sdk.tar"
fi

# ---- 5. trustcache (needed by BaseBin) ---------------------------------------
if ! command -v trustcache >/dev/null 2>&1; then
    echo "[*] Building trustcache ..."
    git clone https://github.com/CRKatri/trustcache /tmp/trustcache
    ( cd /tmp/trustcache
      export CFLAGS="$CFLAGS -I$(brew --prefix openssl@3)/include -arch arm64"
      export LDFLAGS="$LDFLAGS -L$(brew --prefix openssl@3)/lib -arch arm64"
      gmake -j$(sysctl -n hw.logicalcpu) OPENSSL=1
      sudo cp trustcache /opt/procursus/bin/ 2>/dev/null || sudo cp trustcache /usr/local/bin/
    )
fi

# ---- 6. Build ---------------------------------------------------------------
echo "[*] Building ..."
$GMAKE -j$(sysctl -n hw.logicalcpu)

APP_VERSION="$(cat ./BaseBin/_external/basebin/.version)-$(cat ./BaseBin/_external/basebin/.version-roothide)"
echo "[+] Done. Artifacts:"
ls -lh ./Application/Bootmine-roothide-"${APP_VERSION}".ipa
ls -lh ./Application/Bootmine-roothide-"${APP_VERSION}".tipa
echo "[+] Install the .ipa with a sideload tool (TrollStore / TrollBox / AltStore), " \
     "or the .tipa directly with TrollStore."
