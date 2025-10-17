#!/bin/bash

set -exu # -u: exit if referenced variables aren't assigned
         # -e: exit upon command error (NOTE: Builtin operator failures are handled differently depending the shell. POSIX behavior would be to quit, even if the condition was done with `test` )
         # -x: Print values of referenced variables, assignments, conditions and commands as they are executed/evaluated

export APPIMAGE_EXTRACT_AND_RUN=1
export ARCH="$(uname -m)"

SHARUN="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh"
URUNTIME="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/uruntime2appimage.sh"
PELF="https://github.com/xplshn/pelf/releases/latest/download/pelf_$ARCH"

case "$1" in
    common-pgo)
        echo "Making Eden PGO Optimized Build for Modern CPUs"
        CMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5 -O3 -pipe -flto=thin -fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
        CMAKE_C_FLAGS="-march=znver5 -mtune=znver5 -O3 -pipe -flto=thin -fuse-ld=lld -fprofile-use=${GITHUB_WORKSPACE}/pgo/eden.profdata -fprofile-correction -w"
        TARGET="Common-PGO"
  		CC="clang"
		CXX="clang++"
		BUNDLED_SDL2="ON"
  		EXTERNAL_SDL2="OFF"
        ;;
esac

cd ./eden
COUNT="$(git rev-list --count HEAD)"
DATE="$(date +"%d_%m_%Y")"

# hook the updater to check my repo
git apply ../patches/update.patch

#tempfix, remove when upstream fixed
# git apply ../patches/tempfix.patch

mkdir build
cd build
cmake .. -GNinja \
    -DYUZU_USE_BUNDLED_QT=OFF \
	-DYUZU_USE_BUNDLED_FFMPEG=ON \
	-DYUZU_USE_BUNDLED_SIRIT=ON \
	-DYUZU_USE_CPM=ON \
	-DBUILD_TESTING=OFF \
    -DYUZU_TESTS=OFF \
	-DDYNARMIC_TESTS=OFF \
    -DYUZU_ENABLE_LTO=ON \
	-DDYNARMIC_ENABLE_LTO=ON \
    -DENABLE_QT_TRANSLATION=ON \
	-DENABLE_QT_UPDATE_CHECKER=ON \
    -DUSE_DISCORD_PRESENCE=ON \
    -DYUZU_CMD=OFF \
	-DYUZU_ROOM=ON \
    -DYUZU_ROOM_STANDALONE=OFF \
    -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" \
    -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER_LAUNCHER="${CCACHE:-}" \
	-DCMAKE_CXX_COMPILER_LAUNCHER="${CCACHE:-}" \
	-DCMAKE_C_COMPILER="${CC:-}" \
 	-DCMAKE_CXX_COMPILER="${CXX:-}" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--as-needed" \
    ${PROFILE:+-DYUZU_SYSTEM_PROFILE="$PROFILE"} \
	${BUNDLED_SDL2:+-DYUZU_USE_BUNDLED_SDL2="$BUNDLED_SDL2"} \
 	${EXTERNAL_SDL2:+-DYUZU_USE_EXTERNAL_SDL2="$EXTERNAL_SDL2"} \
    ${CMAKE_CXX_FLAGS:+-DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS"} \
    ${CMAKE_C_FLAGS:+-DCMAKE_C_FLAGS="$CMAKE_C_FLAGS"}
ninja
ccache -s -v

# Use sharun to generate AppDir
cd ..
export ICON="$PWD"/dist/dev.eden_emu.eden.svg
export DESKTOP="$PWD"/dist/dev.eden_emu.eden.desktop
export OPTIMIZE_LAUNCH=1
export DEPLOY_OPENGL=1
export DEPLOY_VULKAN=1
export DEPLOY_QT=1
export OUTNAME="Eden-${COUNT}-${TARGET}-${ARCH}.AppImage"

wget -q --retry-connrefused --tries=30 "$SHARUN" -O ./quick-sharun
chmod +x ./quick-sharun
./quick-sharun ./build/bin/eden
echo 'QT_QPA_PLATFORM=xcb' >> AppDir/.env

# Use uruntie to make appimage
wget -q --retry-connrefused --tries=30 "$URUNTIME" -O ./uruntime2appimage
chmod +x ./uruntime2appimage
./uruntime2appimage

mkdir -p appimage
mv -v "${OUTNAME}" appimage/

# Use pelf to make appbundle
wget -q --retry-connrefused --tries=30 "$PELF" -O ./pelf
chmod +x ./pelf

APPBUNDLE="Eden-${COUNT}-${TARGET}-${ARCH}.dwfs.AppBundle"
ln -sfv ./AppDir/eden.svg ./AppDir/.DirIcon.svg
cp -v ../io.github.eden_emu.Eden.appdata.xml ./AppDir
./pelf --add-appdir ./AppDir --appbundle-id="Eden-${DATE}-Escary" --compression "-C zstd:level=22 -S26 -B6" --output-to "$APPBUNDLE"

mkdir -p appbundle
mv -v "${APPBUNDLE}"* appbundle/
