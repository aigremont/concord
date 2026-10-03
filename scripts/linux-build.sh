#!/usr/bin/env bash
# One-shot Linux x86_64 developer build, identical on a throwaway cloud VM and on a
# local Ubuntu 24.04+ workstation: apt deps (the list from .github/workflows/build.yaml),
# vcpkg bootstrap, configure with the ninja-os-mold-ccache preset, build.
#
#   scripts/linux-build.sh            # configure (first run) + build Release
#   scripts/linux-build.sh --deps     # also apt-install the build dependencies (needs sudo)
#   CONFIG=RelWithDebInfo scripts/linux-build.sh
#
# Cache locations are plain directories so they can be rsynced off a VM before it dies and
# restored on the next machine: CCACHE_DIR (default ~/.cache/ccache) and
# VCPKG_DEFAULT_BINARY_CACHE (default ~/.cache/vcpkg-archives). Nothing here is tied to a
# cloud vendor; delete the VM and the same script reproduces the build anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="${PRESET:-ninja-os-mold-ccache}"
CONFIG="${CONFIG:-Release}"
TRIPLET="${TRIPLET:-x64-linux-alchemy-avx2-release}"
BUILD_DIR="$ROOT/build-Linux-$PRESET"

export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache}"
export VCPKG_DEFAULT_BINARY_CACHE="${VCPKG_DEFAULT_BINARY_CACHE:-$HOME/.cache/vcpkg-archives}"
mkdir -p "$CCACHE_DIR" "$VCPKG_DEFAULT_BINARY_CACHE"

if [[ "${1:-}" == "--deps" ]]; then
    sudo apt-get update
    sudo apt-get install -y \
        autoconf autoconf-archive automake bison build-essential ccache cmake curl flex gettext \
        libasound2-dev libaudio-dev libdbus-1-dev libdecor-0-dev libdrm-dev \
        libegl1-mesa-dev libfribidi-dev libgbm-dev libgl1-mesa-dev libgl1-mesa-dri libgles2-mesa-dev \
        libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev libibus-1.0-dev libjack-dev libltdl-dev \
        libpipewire-0.3-dev libpulse-dev libsndio-dev libtext-unidecode-perl \
        libthai-dev libtool libudev-dev libunwind-dev liburing-dev libvlc-dev libwayland-dev \
        libx11-dev libxcursor-dev libxext-dev libxfixes-dev libxft-dev libxi-dev libxinerama-dev \
        libxkbcommon-dev libxrandr-dev libxss-dev libxtst-dev linux-libc-dev mold \
        nasm ninja-build pkgconf python3-pip tar tex-common texinfo unzip zip
    sudo locale-gen en_US.UTF-8
    # The presets need CMake 4.0+; Ubuntu's package is older.
    pip3 install --user --break-system-packages 'cmake>=4.0' ninja llsd
    export PATH="$HOME/.local/bin:$PATH"
    shift
fi

cmake --version | head -1
git -C "$ROOT" submodule update --init --recursive
# indra/cmake/BootstrapVcpkg.cmake bootstraps the vcpkg submodule itself on the first configure.

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    cmake -S "$ROOT/indra" --preset "$PRESET" \
        -DVCPKG_TARGET_TRIPLET="$TRIPLET" \
        -DAL_BUILD_TESTS:BOOL=OFF \
        -DAL_BUILD_PACKAGE:BOOL=OFF \
        -DAL_USE_LTO:BOOL=OFF \
        -DAL_USE_TRACY:BOOL=OFF
fi

cmake --build "$BUILD_DIR" --config "$CONFIG" --parallel "$(nproc)"
ccache -s | head -6 || true
echo "viewer: $BUILD_DIR/newview/$CONFIG/"
