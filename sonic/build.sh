#!/usr/bin/env bash
# Sonic Screwdriver: build asteroid-settings for the watch (rubyfish, AsteroidOS 2.1).
#
#   sonic/build.sh           incremental build
#   sonic/build.sh --clean   start from an empty build directory
#
# Output: sonic/out/asteroid-settings.so (stripped) and its debug symbols,
# sonic/out/asteroid-settings.so.debug. Install it with sonic/deploy.sh.
# The Docker image and the SDK volume are the ones the launcher fork
# (usr-ein/asteroid-launcher) uses; whichever fork builds first sets them up.
# The first setup downloads the AsteroidOS 2.1 SDK (1.2 GB, about 6.5 GB
# installed in a Docker volume). See sonic/BUILD.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
src=$(dirname "$here")
cache=${SONIC_CACHE:-$HOME/.cache/sonic-screwdriver}

# The SDK's Qt 5.15.16 and AsteroidOS libraries are the exact builds on the watch.
sdk=oecore-meta-toolchain-qt5-x86_64-armv7vehf-neon-sturgeon-toolchain-nodistro.0.sh
sdk_url=https://release.asteroidos.org/2.1/sdk/$sdk
sdk_sha512=90dbbaf5c5ae26471a7d874549cb8c6f7247245eb9d475465ee4fff290a335beb3d336167da6671a7397b46046c499db55aef47c3056c3307da521b5faa52e40
sdk_dir=/opt/asteroid-sdk

# Shared with the launcher fork: same image, same SDK volume.
image=sonic-asteroid-launcher-sdk:2.1
sdk_volume=sonic-asteroid-sdk-2.1
build_volume=sonic-asteroid-settings-build

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
run() { docker run --rm --platform linux/amd64 "$@"; }

clean=0
case "${1:-}" in
	--clean) clean=1 ;;
	"") ;;
	*) echo "usage: $0 [--clean]" >&2; exit 64 ;;
esac

if ! docker image inspect "$image" >/dev/null 2>&1; then
	log "building the Docker image $image"
	docker build --platform linux/amd64 -t "$image" "$here"
fi

if ! run -v "$sdk_volume:$sdk_dir" "$image" test -f "$sdk_dir/environment-setup-armv7vehf-neon-oe-linux-gnueabi"; then
	dl=$cache/asteroid-sdk-2.1
	mkdir -p "$dl"
	if ! echo "$sdk_sha512  $dl/$sdk" | shasum -a 512 -c - >/dev/null 2>&1; then
		log "downloading the AsteroidOS 2.1 SDK (1.2 GB)"
		curl -fL --retry 3 -C - -o "$dl/$sdk" "$sdk_url"
		echo "$sdk_sha512  $dl/$sdk" | shasum -a 512 -c -
	fi
	log "installing the SDK into the Docker volume $sdk_volume"
	run -v "$sdk_volume:$sdk_dir" -v "$dl:/dl:ro" "$image" sh "/dl/$sdk" -y -d "$sdk_dir"
fi

if [ $clean = 1 ]; then
	log "emptying the build directory"
	run -v "$build_volume:/build" "$image" sh -c 'rm -rf /build/* /build/.[!.]*'
fi

log "building asteroid-settings"
mkdir -p "$here/out"
run -v "$sdk_volume:$sdk_dir:ro" -v "$build_volume:/build" -v "$src:/src:ro" -v "$here/out:/out" \
	"$image" bash -ec '
	. '"$sdk_dir"'/environment-setup-armv7vehf-neon-oe-linux-gnueabi
	cmake -S /src -B /build -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
	cmake --build /build -j"$(nproc)"
	$OBJCOPY --only-keep-debug /build/src/asteroid-settings.so /out/asteroid-settings.so.debug
	$STRIP -o /out/asteroid-settings.so /build/src/asteroid-settings.so
	$OBJCOPY --add-gnu-debuglink=/out/asteroid-settings.so.debug /out/asteroid-settings.so
'
log "built $(cd "$here/out" && ls -l asteroid-settings.so | awk '{print $5}') bytes: sonic/out/asteroid-settings.so ($(git -C "$src" describe --always --dirty))"
