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
GITHUB_HTTPS_PROXY="${GITHUB_HTTPS_PROXY:-${https_proxy:-10.0.8.118:20172}}"

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

clean_runtime_env() {
  env \
    -u CYCLONEDDS_HOME \
    -u CMAKE_PREFIX_PATH \
    -u DDSHOME \
    -u LD_LIBRARY_PATH \
    -u CPATH \
    -u C_INCLUDE_PATH \
    -u CPLUS_INCLUDE_PATH \
    -u LIBRARY_PATH \
    -u PKG_CONFIG_PATH \
    "$@"
}

git_https() {
  env https_proxy="$GITHUB_HTTPS_PROXY" HTTPS_PROXY="$GITHUB_HTTPS_PROXY" git "$@"
}

prefix_libdir() {
  local prefix="$1"

  if [ -d "$prefix/lib" ]; then
    echo "$prefix/lib"
  elif [ -d "$prefix/lib64" ]; then
    echo "$prefix/lib64"
  else
    die "CycloneDDS library directory not found under $prefix"
  fi
}

verify_cyclonedds_wheel() {
  local wheel="$1"

  "$PYTHON_BIN" - "$wheel" <<'PY'
import sys
import zipfile

wheel = sys.argv[1]
with zipfile.ZipFile(wheel) as zf:
    names = set(zf.namelist())
    library_py = zf.read("cyclonedds/__library__.py").decode()

if "in_wheel = True" not in library_py:
    raise SystemExit(f"{wheel}: cyclonedds/__library__.py is not configured for bundled libraries")
if "cyclonedds.libs" not in library_py:
    raise SystemExit(f"{wheel}: cyclonedds/__library__.py does not look in cyclonedds.libs")
if not any(name.startswith("cyclonedds.libs/libddsc") for name in names):
    raise SystemExit(f"{wheel}: bundled libddsc is missing")
if not any(name.startswith("cyclonedds.libs/libcycloneddsidl") for name in names):
    raise SystemExit(f"{wheel}: bundled libcycloneddsidl is missing")

print(f"Verified bundled CycloneDDS libraries in {wheel}")
PY
}

clone_cyclonedds_c() {
  local ver="$1"
  local src="$ROOT/src/cyclonedds-$ver"

  if [ -d "$src/.git" ]; then
    log "Updating CycloneDDS C source $ver"
    git_https -C "$src" fetch --tags --force
  else
    log "Cloning CycloneDDS C source $ver"
    git_https clone "$CYCLONEDDS_REPO" "$src"
    git_https -C "$src" fetch --tags --force
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
  local libdir

  log "Building Python wheel cyclonedds==$ver"

  clean_env_for_build

  rm -rf "$raw" "$out"
  mkdir -p "$raw" "$out"

  libdir="$(prefix_libdir "$prefix")"

  export CYCLONEDDS_HOME="$prefix"
  export CMAKE_PREFIX_PATH="$prefix"
  export STANDALONE_WHEELS=1
  export PATH="$prefix/bin:$PATH"
  export LD_LIBRARY_PATH="$libdir"
  export LIBRARY_PATH="$libdir"
  export PKG_CONFIG_PATH="$libdir/pkgconfig"

  "$venv/bin/python" -m pip wheel \
    --no-cache-dir \
    --no-binary cyclonedds \
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

    LD_LIBRARY_PATH="$libdir" "$venv/bin/python" -m auditwheel show "$built"

    LD_LIBRARY_PATH="$libdir" "$venv/bin/python" -m auditwheel repair \
      -w "$out" \
      "$built" \
      2>&1 | tee "$ROOT/logs/auditwheel-$ver.log"
  else
    echo "WARNING: AUDITWHEEL=0 produces a non-portable raw wheel on Linux."
    cp -v "$built" "$out/"
  fi

  local final
  final="$(find "$out" -maxdepth 1 -name "cyclonedds-${ver}-*.whl" | head -n 1 || true)"
  if [ -z "$final" ]; then
    die "cyclonedds==$ver final wheel was not produced"
  fi

  if [ "$AUDITWHEEL" = "1" ]; then
    verify_cyclonedds_wheel "$final"
  fi

  # 同步复制依赖 wheel，例如 rich-click / click 等
  find "$raw" -maxdepth 1 -type f -name "*.whl" ! -name "cyclonedds-${ver}-*.whl" \
    -exec cp --update=none -v {} "$out/" \;

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

  clean_runtime_env "$test_venv/bin/cyclonedds" --help >/dev/null

  clean_runtime_env "$test_venv/bin/python" - <<'PY'
from dataclasses import dataclass
from pathlib import Path
from time import sleep
import os

import cyclonedds
from cyclonedds.__library__ import in_wheel, library_path
from cyclonedds.core import Qos, Policy
from cyclonedds.domain import DomainParticipant
from cyclonedds.idl import IdlStruct
from cyclonedds.idl.annotations import key
from cyclonedds.pub import DataWriter
from cyclonedds.sub import DataReader
from cyclonedds.topic import Topic

assert in_wheel, "cyclonedds is not configured to load bundled libraries"
assert Path(library_path).exists(), f"bundled libddsc does not exist: {library_path}"

@dataclass
class Chatter(IdlStruct, typename="CodexChatter"):
    name: str
    key("name")
    message: str
    count: int

participant = DomainParticipant()
topic = Topic(
    participant,
    f"codex_script_smoke_{os.getpid()}",
    Chatter,
    qos=Qos(Policy.Reliability.Reliable(0)),
)
writer = DataWriter(participant, topic)
reader = DataReader(participant, topic)
writer.write(Chatter(name="codex", message="ok", count=1))

for _ in range(20):
    samples = reader.take(10)
    if samples:
        assert samples[0].message == "ok"
        break
    sleep(0.1)
else:
    raise SystemExit("DDS smoke test did not receive its own sample")

print("cyclonedds import/CLI/DDS smoke OK")
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
