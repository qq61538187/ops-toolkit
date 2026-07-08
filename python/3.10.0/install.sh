#!/usr/bin/env bash
#
# install.sh — 安装 Python 3.10.0（系统包管理器）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget/官方安装包，见文末提示）
#
# 关于版本：系统包管理器提供的是「发行版仓库当前的 Python 3」，其 patch 版本
#           通常不等于这里写死的 3.10.0。脚本把 3.10.0 视为「目标版本」：
#           - Ubuntu/Debian 可用 USE_DEADSNAKES=1 精确安装 python3.10 系列；
#           - 安装后做校验，版本不符只告警、不失败。
#
# 用法：
#   ./install.sh                     # 安装发行版默认的 python3（含 pip、venv）
#   USE_DEADSNAKES=1 ./install.sh    # Ubuntu/Debian：加 deadsnakes PPA 装 python3.10
#
set -euo pipefail

PY_VERSION="3.10.0"                    # 目标版本（仓库实际提供的 patch 可能不同）
PY_SERIES="${PY_VERSION%.*}"          # -> 3.10（deadsnakes 以系列为粒度）

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 winget 安装，例如：
         winget install --id Python.Python.3.10 -e" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 探测包管理器 ----------------------------------------------------------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
  elif command -v yum     >/dev/null 2>&1; then PM="yum"
  elif command -v brew    >/dev/null 2>&1; then PM="brew"
  else die "未找到受支持的包管理器（apt-get / dnf / yum / brew）"; fi
}

setup_privilege() {
  SUDO=""
  if [ "$PM" = "brew" ]; then
    [ "$(id -u)" -eq 0 ] && die "Homebrew 不能以 root 运行，请用普通用户执行。"
    return
  fi
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      die "需要 root 权限安装系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

# 优先用精确解释器（如 python3.10），否则回退到 python3
resolve_python() {
  if command -v "python${PY_SERIES}" >/dev/null 2>&1; then
    PY_BIN="python${PY_SERIES}"
  elif command -v python3 >/dev/null 2>&1; then
    PY_BIN="python3"
  else
    PY_BIN=""
  fi
}

installed_version() {
  resolve_python
  [ -n "$PY_BIN" ] || return 0
  "$PY_BIN" -c 'import platform; print(platform.python_version())' 2>/dev/null
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  if [ -n "${USE_DEADSNAKES:-}" ]; then
    log "启用 deadsnakes PPA 并安装 python${PY_SERIES} 系列"
    if ! command -v add-apt-repository >/dev/null 2>&1; then
      $SUDO apt-get update -y
      $SUDO apt-get install -y software-properties-common
    fi
    $SUDO add-apt-repository -y ppa:deadsnakes/ppa || warn "添加 deadsnakes 失败，改用发行版自带 python3"
    $SUDO apt-get update -y
    $SUDO apt-get install -y "python${PY_SERIES}" "python${PY_SERIES}-venv" "python${PY_SERIES}-dev" \
      || { warn "python${PY_SERIES} 安装失败，回退安装 python3"; $SUDO apt-get install -y python3 python3-venv python3-dev python3-pip; }
    # deadsnakes 不带 pip，用 ensurepip 引导
    "python${PY_SERIES}" -m ensurepip --upgrade 2>/dev/null || true
  else
    log "apt-get 安装 python3（含 pip、venv、dev）..."
    $SUDO apt-get update -y
    $SUDO apt-get install -y python3 python3-pip python3-venv python3-dev
  fi
}

install_dnf() {
  log "dnf 安装 python3 ..."
  $SUDO dnf install -y python3 python3-pip || die "dnf 安装 python3 失败"
  $SUDO dnf install -y python3-devel 2>/dev/null || true
}
install_yum() {
  log "yum 安装 python3 ..."
  $SUDO yum install -y python3 python3-pip || die "yum 安装 python3 失败"
  $SUDO yum install -y python3-devel 2>/dev/null || true
}
install_brew() {
  log "brew 安装 python@${PY_SERIES} ..."
  brew install "python@${PY_SERIES}" 2>/dev/null || { warn "python@${PY_SERIES} 不可用，改装最新 python3"; brew install python3; }
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "目标：Python ${PY_VERSION}（经由 ${PM}）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_dnf ;;
  yum)  install_yum ;;
  brew) install_brew ;;
esac

# ---- 验证 ------------------------------------------------------------------
actual="$(installed_version)"
[ -n "$actual" ] || die "安装后未找到 python 解释器"

log "已安装：Python ${actual}（$(command -v "$PY_BIN")）"
log "pip：$("$PY_BIN" -m pip --version 2>/dev/null || echo '未检测到，可执行 '"$PY_BIN"' -m ensurepip --upgrade')"

if [ "$actual" = "$PY_VERSION" ]; then
  log "版本与目标一致：${PY_VERSION}"
elif [ "${actual%.*}" = "$PY_SERIES" ]; then
  warn "已装 ${actual}，属目标系列 ${PY_SERIES}，但 patch 与 ${PY_VERSION} 不同 —— 系统仓库通常只提供该系列的某个 patch。"
else
  warn "实际版本 ${actual} 与目标 ${PY_VERSION} 不一致。"
  warn "如需精确的 ${PY_VERSION}："
  warn "  · Ubuntu/Debian：USE_DEADSNAKES=1 ./install.sh 重试（可装 python${PY_SERIES} 系列）"
  warn "  · 或改用 pyenv / 源码编译到独立 PREFIX（可精确锁定 patch 版本）。"
fi
