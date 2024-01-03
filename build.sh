#!/bin/bash
set -e
export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1
NO_SYS_MUSL=1

musl_version="1.2.4"

platform="$(uname -s)"
platform_arch="$(uname -m)"

if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt update && apt install -y \
            build-essential clang pkg-config git autoconf libtool \
            gettext autopoint po4a upx doxygen meson ninja-build
fi

[ "$musl_version" == "latest" ] && \
  musl_version="$(curl -s https://www.musl-libc.org/releases/|tac|grep -v 'latest'|\
                  grep -om1 'musl-.*\.tar\.gz'|cut -d'>' -f2|sed 's|musl-||g;s|.tar.gz||g')"

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [ -d release ]
    then
        echo "= removing previous release directory"
        rm -rf release
fi

# create build and release directory
mkdir build
mkdir -p release
pushd build

# download zstd
git clone https://github.com/facebook/zstd.git
zstd_version="$(cd zstd && git describe --long --tags|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
echo "= downloading zstd v${zstd_version}"
mv zstd "zstd-$zstd_version"

if [ "$platform" == "Linux" ]
    then
        echo "= setting CC to musl-gcc"
        if [[ ! -x "$(which musl-gcc 2>/dev/null)" || "$NO_SYS_MUSL" == 1 ]]
            then
                echo "= downloading musl v${musl_version}"
                curl -LO https://www.musl-libc.org/releases/musl-${musl_version}.tar.gz

                echo "= extracting musl"
                tar -xf musl-${musl_version}.tar.gz

                echo "= building musl"
                working_dir="$(pwd)"

                install_dir="${working_dir}/musl-install"

                pushd musl-${musl_version}
                env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" LDFLAGS='-Wl,--gc-sections' ./configure --prefix="${install_dir}"
                make install
                popd # musl-${musl-version}
                export CC="${working_dir}/musl-install/bin/musl-gcc"
            else
                export CC="$(which musl-gcc 2>/dev/null)"
        fi
        export CFLAGS="-static"
        export LDFLAGS='-static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building zstd"
pushd zstd-${zstd_version}
meson setup \
    -Dbin_programs=true \
    -Dstatic_runtime=true \
    -Ddefault_library=static \
    -Dzlib=disabled -Dlzma=disabled -Dlz4=disabled \
    build/meson builddir && \
ninja -C builddir
popd # zstd-${zstd_version}

popd # build

shopt -s extglob

echo "= extracting zstd binary/lib"
mv "build/zstd-${zstd_version}/builddir/programs/zstd" release 2>/dev/null
mv "build/zstd-${zstd_version}/builddir/lib/libzstd.a" release 2>/dev/null

echo "= striptease"
strip -s -R .comment -R .gnu.version --strip-unneeded release/zstd 2>/dev/null

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        upx -9 --best release/zstd 2>/dev/null
fi

echo "= create release tar.xz"
tar --xz -acf zstd-static-v${zstd_version}-${platform_arch}.tar.xz release

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release build
fi

echo "= zstd v${zstd_version} done"
