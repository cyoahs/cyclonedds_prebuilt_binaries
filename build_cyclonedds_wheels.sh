#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   chmod +x build_cyclonedds_wheels_isolated.sh
#   ./build_cyclonedds_wheels_isolated.sh 0.10.2 0.10.5
#
# Optional:
#   PYTHON_BIN=python3.12 ./build_cyclonedds_wheels_isolated.sh 0.10.2
#   ROOT=/data/build_cyclonedds ./build_cyclonedds_wheels_isolated.sh 0.10.2
#   JOBS=12 ./build_cyclonedds_wheels_isolated.sh 0.10.2
#   AUDITWHEEL=0 ./build_cyclonedds_wheels_isolated.sh 0.10.2

PYTHON_BIN="${PYTHON_BIN:-python3}"
ROOT="${ROOT:-$PWD/cyclonedds_wheel_build}"
JOBS="${JOBS:-$(nproc)}"
AUDITWHEEL="${AUDITWHEEL:-1}"
CYCLONEDDS_REPO="${CYCLONEDDS_REPO:-https://github.com/eclipse-cyclonedds/cyclonedds.git}"

VERSIONS=("$@")
if [ "${#VERSIONS[@]}" -eq 0 ]; then
  VERSIONS=("0.10.2")
fi

mkdir -p "$ROOT"/{src,build,install,venv,raw_wheels,wheelhouse,logs}

log() {
  echo
  echo "========== $* =========="
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

check_cmd git
check_cmd cmake
check_cmd "$PYTHON_BIN"

if [ "$AUDITWHEEL" = "1" ]; then
  check_cmd patchelf || {
    echo "WARNING: patchelf not found."
    echo "Install with:"
    echo "  sudo apt-get install -y patchelf"
    echo "auditwheel repair may fail without it."
  }
fi

log "Python info"
"$PYTHON_BIN" - <<'PY'
import sys
print(sys.executable)
print(sys.version)
PY

# 避免继承用户 shell / 系统里的 DDS 环境
clean_env_for_build() {
  unset CYCLONEDDS_HOME || true
  unset CMAKE_PREFIX_PATH || true
  unset DDSHOME || true
  unset LD_LIBRARY_PATH || true
  unset CPATH || true
  unset C_INCLUDE_PATH || true
  unset CPLUS_INCLUDE_PATH || true
  unset LIBRARY_PATH || true
  unset PKG_CONFIG_PATH || true
}

clone_cyclonedds_c() {
  local ver="$1"
  local src="$ROOT/src/cyclonedds-$ver"

  if [ -d "$src/.git" ]; then
    log "Updating CycloneDDS C source $ver"
    git -C "$src" fetch --tags --force
  else
    log "Cloning CycloneDDS C source $ver"
    git clone "$CYCLONEDDS_REPO" "$src"
    git -C "$src" fetch --tags --force
  fi

  if git -C "$src" rev-parse -q --verify "refs/tags/$ver" >/dev/null; then
    git -C "$src" checkout -f "tags/$ver"
  elif git -C "$src" rev-parse -q --verify "refs/tags/v$ver" >/dev/null; then
    git -C "$src" checkout -f "tags/v$ver"
  else
    die "Cannot find CycloneDDS C tag $ver or v$ver"
  fi

  git -C "$src" clean -fdx
}

build_cyclonedds_c() {
  local ver="$1"

  local src="$ROOT/src/cyclonedds-$ver"
  local bld="$ROOT/build/cyclonedds-$ver"
  local prefix="$ROOT/install/cyclonedds-$ver"

  log "Building CycloneDDS C library $ver"

  clean_env_for_build

  rm -rf "$bld" "$prefix"
  mkdir -p "$bld" "$prefix"

  cmake -S "$src" -B "$bld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_SSL=OFF \
    -DENABLE_SECURITY=OFF \
    -DENABLE_ICEORYX=OFF

  cmake --build "$bld" --target install -j "$JOBS"

  if [ ! -f "$prefix/lib/libddsc.so" ] && [ ! -f "$prefix/lib64/libddsc.so" ]; then
    die "libddsc.so not found under $prefix"
  fi

  echo "CycloneDDS C installed to:"
  echo "  $prefix"
}

create_build_venv() {
  local ver="$1"
  local venv="$ROOT/venv/cyclonedds-$ver"

  log "Creating isolated Python venv for cyclonedds==$ver"

  rm -rf "$venv"
  "$PYTHON_BIN" -m venv "$venv"

  "$venv/bin/python" -m pip install -U pip setuptools wheel build

  if [ "$AUDITWHEEL" = "1" ]; then
    "$venv/bin/python" -m pip install -U auditwheel
  fi

  "$venv/bin/python" - <<'PY'
import sys
print("Build venv Python:", sys.executable)
print("Version:", sys.version)
PY
}

build_python_wheel() {
  local ver="$1"

  local prefix="$ROOT/install/cyclonedds-$ver"
  local venv="$ROOT/venv/cyclonedds-$ver"
  local raw="$ROOT/raw_wheels/$ver"
  local out="$ROOT/wheelhouse/$ver"

  log "Building Python wheel cyclonedds==$ver"

  clean_env_for_build

  rm -rf "$raw" "$out"
  mkdir -p "$raw" "$out"

  export CYCLONEDDS_HOME="$prefix"
  export CMAKE_PREFIX_PATH="$prefix"
  export PATH="$prefix/bin:$PATH"

  if [ -d "$prefix/lib" ]; then
    export LD_LIBRARY_PATH="$prefix/lib"
  elif [ -d "$prefix/lib64" ]; then
    export LD_LIBRARY_PATH="$prefix/lib64"
  fi

  "$venv/bin/python" -m pip wheel \
    --no-binary=cyclonedds \
    "cyclonedds==$ver" \
    -w "$raw" \
    2>&1 | tee "$ROOT/logs/pip-wheel-cyclonedds-$ver.log"

  local built
  built="$(find "$raw" -maxdepth 1 -name "cyclonedds-${ver}-*.whl" | head -n 1 || true)"

  if [ -z "$built" ]; then
    die "cyclonedds==$ver wheel was not produced"
  fi

  if [ "$AUDITWHEEL" = "1" ]; then
    log "Running auditwheel for cyclonedds==$ver"

    "$venv/bin/python" -m auditwheel show "$built" || true

    "$venv/bin/python" -m auditwheel repair \
      -w "$out" \
      "$built" \
      2>&1 | tee "$ROOT/logs/auditwheel-$ver.log" || {
        echo "WARNING: auditwheel repair failed."
        echo "Copying raw wheel instead:"
        cp -v "$built" "$out/"
      }
  else
    cp -v "$built" "$out/"
  fi

  # 同步复制依赖 wheel，例如 rich-click / click 等
  find "$raw" -maxdepth 1 -type f -name "*.whl" ! -name "cyclonedds-${ver}-*.whl" \
    -exec cp -nv {} "$out/" \;

  log "Finished cyclonedds==$ver"
  echo "Wheelhouse:"
  echo "  $out"
  ls -lh "$out"
}

test_wheel_install() {
  local ver="$1"

  local test_venv="$ROOT/venv/test-cyclonedds-$ver"
  local out="$ROOT/wheelhouse/$ver"

  log "Testing wheel install cyclonedds==$ver"

  rm -rf "$test_venv"
  "$PYTHON_BIN" -m venv "$test_venv"

  "$test_venv/bin/python" -m pip install -U pip >/dev/null

  "$test_venv/bin/python" -m pip install \
    --no-index \
    --find-links="$out" \
    "cyclonedds==$ver"

  "$test_venv/bin/python" - <<'PY'
import cyclonedds
print("cyclonedds import OK")
print(cyclonedds)
PY
}

for ver in "${VERSIONS[@]}"; do
  clone_cyclonedds_c "$ver"
  build_cyclonedds_c "$ver"
  create_build_venv "$ver"
  build_python_wheel "$ver"
  test_wheel_install "$ver"
done

log "All done"

echo "Output wheelhouses:"
find "$ROOT/wheelhouse" -mindepth 1 -maxdepth 1 -type d -print

echo
echo "Example install:"
for ver in "${VERSIONS[@]}"; do
  echo "  pip install --no-index --find-links=$ROOT/wheelhouse/$ver cyclonedds==$ver"
done