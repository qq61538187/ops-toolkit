#!/usr/bin/env bash
#
# install.sh — 安装 Python 2.7.18（系统包管理器）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#
# ⚠ Python 2 已于 2020-01-01 停止官方维护（EOL），2.7.18 是最后一个发布版本。
#   新项目请勿使用；此脚本仅用于维护存量遗留系统。多数较新发行版的默认仓库
#   已不再提供 python2，届时脚本会给出替代方案（pyenv / 源码编译 / EOL 仓库）。
#
# 关于版本：系统仓库提供的 python2 其 patch 版本通常就是 2.7.18（2.7 末版），
#           但不同发行版可能略有差异；脚本把 2.7.18 视为「目标版本」并在装后校验。
#
# 用法：
#   ./install.sh                 # 用系统包管理器安装 python2 + pip2
#
set -euo pipefail

PY_VERSION="2.7.18"
PY_SERIES="${PY_VERSION%.*}"          # -> 2.7

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请到 python.org 下载 2.7.18 安装包（已 EOL）。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

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

resolve_python() {
  if   command -v python2.7 >/dev/null 2>&1; then PY_BIN="python2.7"
  elif command -v python2   >/dev/null 2>&1; then PY_BIN="python2"
  else PY_BIN=""; fi
}

installed_version() {
  resolve_python
  [ -n "$PY_BIN" ] || return 0
  # Python 2 的 --version 输出到 stderr
  "$PY_BIN" --version 2>&1 | awk '{print $2}'
}

eol_hint() {
  warn "如需精确的 Python ${PY_VERSION}（该系列已 EOL）："
  warn "  · 推荐 pyenv：pyenv install 2.7.18（从源码编译，隔离于系统）"
  warn "  · 或手动编译：https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz"
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  log "apt-get 安装 python2 ..."
  $SUDO apt-get update -y
  if $SUDO apt-get install -y python2 python2-dev 2>/dev/null \
     || $SUDO apt-get install -y python2.7 python2.7-dev 2>/dev/null; then
    :
  else
    warn "当前仓库未提供 python2/python2.7（较新的 Ubuntu/Debian 已移除）。"
    eol_hint
    die "无法通过 apt 安装 python2。"
  fi
  bootstrap_pip2
}

install_dnf() {
  log "dnf 安装 python2 ..."
  if $SUDO dnf install -y python2 2>/dev/null; then
    $SUDO dnf install -y python2-pip python2-devel 2>/dev/null || true
  else
    warn "当前仓库未提供 python2（RHEL/Rocky 8+ 默认已无）。"
    eol_hint
    die "无法通过 dnf 安装 python2。"
  fi
}

install_yum() {
  log "yum 安装 python2 ..."
  if $SUDO yum install -y python2 2>/dev/null || $SUDO yum install -y python 2>/dev/null; then
    $SUDO yum install -y python2-pip python-devel 2>/dev/null || true
  else
    warn "当前仓库未提供 python2。"
    eol_hint
    die "无法通过 yum 安装 python2。"
  fi
}

install_brew() {
  warn "Homebrew 已移除 python@2 formula（EOL）。"
  eol_hint
  die "无法通过 brew 安装 Python 2。推荐使用 pyenv：brew install pyenv && pyenv install 2.7.18"
}

# pip for Python2：优先系统包，其次 ensurepip，最后 get-pip（旧版）
bootstrap_pip2() {
  resolve_python
  [ -n "$PY_BIN" ] || return 0
  if "$PY_BIN" -m pip --version >/dev/null 2>&1; then return 0; fi
  $SUDO apt-get install -y python-pip 2>/dev/null || true
  "$PY_BIN" -m ensurepip 2>/dev/null || true
  if ! "$PY_BIN" -m pip --version >/dev/null 2>&1; then
    warn "未能自动装好 pip2；如需可手动执行："
    warn "  curl -sSLO https://bootstrap.pypa.io/pip/2.7/get-pip.py && ${PY_BIN} get-pip.py"
  fi
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

warn "注意：Python 2 已于 2020-01-01 EOL，仅建议用于维护遗留系统。"
log "目标：Python ${PY_VERSION}（经由 ${PM}）"

case "$PM" in
  apt)  install_apt ;;
  dnf)  install_dnf ;;
  yum)  install_yum ;;
  brew) install_brew ;;
esac

# ---- 验证 ------------------------------------------------------------------
actual="$(installed_version)"
[ -n "$actual" ] || die "安装后未找到 python2 解释器"

log "已安装：Python ${actual}（$(command -v "$PY_BIN")）"
log "pip：$("$PY_BIN" -m pip --version 2>/dev/null || echo '未检测到')"

if [ "$actual" = "$PY_VERSION" ]; then
  log "版本与目标一致：${PY_VERSION}"
elif [ "${actual%.*}" = "$PY_SERIES" ]; then
  warn "已装 ${actual}，属目标系列 ${PY_SERIES}，patch 与 ${PY_VERSION} 略有出入（发行版打包所致）。"
else
  warn "实际版本 ${actual} 与目标 ${PY_VERSION} 不一致。"
  eol_hint
fi
