#!/usr/bin/env bash

set -ex

export ARCH="amd64"
export CC=clang20
export CXX=clang++20
export LD=ld.lld20

cd ./eden
git config --global --add safe.directory .
COUNT="$(git rev-list --count HEAD)"

# hook the updater to check my repo
git apply ../patches/update.patch

#tempfix, remove when upstream fixed
# git apply ../patches/tempfix.patch

if [ "$TARGET" = "Solaris" ]; then
    QT6_DIR="$(find /usr -name Qt6Config.cmake 2>/dev/null | head -n1 | xargs dirname)"
elif [ "$TARGET" = "FreeBSD" ]; then
    QT6_DIR="/usr/local/lib/cmake/Qt6"
fi

declare -a EXTRA_CMAKE_FLAGS=()
if [[ "${OPTIMIZE}" == "PGO" ]]; then
    EXTRA_CMAKE_FLAGS+=(
        "-DCMAKE_CXX_FLAGS=-O3 -pipe -fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
        "-DCMAKE_C_FLAGS=-O3 -pipe -fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
    )
else
    EXTRA_CMAKE_FLAGS+=(
    "-DCMAKE_CXX_FLAGS=-O3 -pipe -fuse-ld=lld -w"
    "-DCMAKE_C_FLAGS=-O3 -pipe -fuse-ld=lld -w"
    )
fi

mkdir -p build
cd build
cmake .. -GNinja \
    -DYUZU_TESTS=OFF \
    -DYUZU_USE_BUNDLED_QT=OFF \
    -DYUZU_USE_BUNDLED_SIRIT=ON \
    -DYUZU_ENABLE_LTO=ON \
    -DYUZU_USE_CPM=ON \
    -DYUZU_USE_FASTER_LD=OFF \
    -DENABLE_QT_TRANSLATION=ON \
    -DENABLE_QT_UPDATE_CHECKER=ON \
    -DUSE_DISCORD_PRESENCE=OFF \
    -DYUZU_CMD=OFF \
    -DYUZU_ROOM_STANDALONE=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DQt6_DIR="${QT6_DIR}" \
    "${EXTRA_CMAKE_FLAGS[@]}"
ninja

PKG_NAME="Eden-${COUNT}-${TARGET}-${ARCH}"
PKG_DIR="${PKG_NAME}/usr/local"
EDEN_PATH="${PKG_DIR}/bin/eden"

# Create base pkg dir
mkdir -p "${PKG_DIR}/bin"
cp -v ./bin/eden "${PKG_DIR}/bin"
mkdir -p "${PKG_DIR}/share/applications/"
cp -v ../dist/dev.eden_emu.eden.desktop "${PKG_DIR}/share/applications/"
mkdir -p "${PKG_DIR}/share/icons/hicolor/scalable/apps/"
cp -v ../dist/dev.eden_emu.eden.svg "${PKG_DIR}/share/icons/hicolor/scalable/apps/"

mkdir -p "${PKG_DIR}/lib/qt6"

# Copy all linked libs
ldd "$EDEN_PATH" | awk '/=>/ {print $3}' | while read -r lib; do
  case "$lib" in
    /lib*|/usr/lib*) ;;  # Skip system libs
    *)
      if echo "$lib" | grep -q '^/usr/local/lib/qt6/'; then
        cp -v "$lib" "${PKG_DIR}/lib/qt6/"
      else
        cp -v "$lib" "${PKG_DIR}/lib/"
      fi
      ;;
  esac
done

# Copy Qt6 plugins
QT6_PLUGINS="/usr/local/lib/qt6/plugins"
QT6_PLUGIN_SUBDIRS="
imageformats
iconengines
platforms
platformthemes
platforminputcontexts
styles
xcbglintegrations
wayland-decoration-client
wayland-graphics-integration-client
wayland-graphics-integration
wayland-shell-integration
"

for sub in $QT6_PLUGIN_SUBDIRS; do
  if [ -d "${QT6_PLUGINS}/${sub}" ]; then
    mkdir -p "${PKG_DIR}/lib/qt6/plugins/${sub}"
    cp -rv "${QT6_PLUGINS}/${sub}"/* "${PKG_DIR}/lib/qt6/plugins/${sub}/"
  fi
done

# Copy Qt6 translations
mkdir -p "${PKG_DIR}/share/translations"
cp -v src/yuzu/*.qm "${PKG_DIR}/share/translations/"

# Strip binaries
strip "${PKG_DIR}/bin/eden"
find "${PKG_DIR}/lib" -type f -name '*.so*' -exec strip {} \;

# Create a laucher for the pack
cat > "${PKG_NAME}/launch.sh" <<EOF
#!/bin/sh
# Eden Launcher for "${TARGET}"

DIR=\$(dirname "\$0")/usr/local

# Setup libs environment
export LD_LIBRARY_PATH="\$DIR/lib:\$DIR/lib/qt6:\$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="\$DIR/lib/qt6/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="\$QT_PLUGIN_PATH/platforms"
export QT_TRANSLATIONS_PATH="\$DIR/share/translations"

exec "\$DIR/bin/eden" "\$@"
EOF

chmod +x "${PKG_NAME}/launch.sh"

# Pack for upload
XZ_OPT="-9e -T0" tar -cavf "${PKG_NAME}.tar.xz" "${PKG_NAME}"
mkdir -p artifacts
mv -v "${PKG_NAME}.tar.xz" artifacts

echo "Build completed successfully."
