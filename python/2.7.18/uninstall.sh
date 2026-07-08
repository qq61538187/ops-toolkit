#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Python 2.7（对应 install.sh 的系统包管理器安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#
# 说明：卸载系统包管理器安装的 python2 / python2.7。较老系统上仍可能有组件
#       依赖 python2，卸载前包管理器会给出依赖提示；如遇阻断请自行评估。
#
# 用法：
#   ./uninstall.sh                 # 卸载 python2 / python2.7 及其 pip、dev 包
#   PURGE=1 ./uninstall.sh         # apt：purge（连同配置一起清理）
#
set -euo pipefail

PY_VERSION="2.7.18"
PY_SERIES="${PY_VERSION%.*}"          # -> 2.7

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测（与 install.sh 一致）--------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请用控制面板卸载 Python 2。" ;;
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
      die "需要 root 权限卸载系统包，且未找到 sudo，请以 root 重试。"
    fi
  fi
}

resolve_python() {
  if   command -v python2.7 >/dev/null 2>&1; then PY_BIN="python2.7"
  elif command -v python2   >/dev/null 2>&1; then PY_BIN="python2"
  else PY_BIN=""; fi
}

# ---- 各包管理器的卸载动作 --------------------------------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  local pkgs=()
  for p in python2 python2.7 python2-dev python2.7-dev python-pip; do
    dpkg -l "$p" >/dev/null 2>&1 && pkgs+=("$p")
  done
  if [ "${#pkgs[@]}" -eq 0 ]; then
    warn "未发现已安装的 python2 相关 apt 包"
    return 1
  fi
  if [ -n "${PURGE:-}" ]; then
    log "apt-get purge: ${pkgs[*]}"
    $SUDO apt-get purge -y "${pkgs[@]}"
  else
    log "apt-get remove: ${pkgs[*]}"
    $SUDO apt-get remove -y "${pkgs[@]}"
  fi
  $SUDO apt-get autoremove -y || true
  return 0
}

remove_rpm() {
  local mgr="$1" pkgs=()
  for p in python2 python2-pip python2-devel; do
    rpm -q "$p" >/dev/null 2>&1 && pkgs+=("$p")
  done
  if [ "${#pkgs[@]}" -eq 0 ]; then
    warn "未发现已安装的 python2 相关 rpm 包"
    return 1
  fi
  log "${mgr} remove: ${pkgs[*]}"
  $SUDO "$mgr" remove -y "${pkgs[@]}"
  return 0
}

remove_brew() {
  if brew list --formula python@2 >/dev/null 2>&1; then
    log "brew uninstall python@2 ..."
    brew uninstall python@2
    return 0
  fi
  warn "Homebrew 未安装 python@2（该 formula 已被移除），无需卸载"
  return 1
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

before="$(resolve_python; echo "${PY_BIN:-}")"
log "准备卸载 Python ${PY_SERIES}（经由 ${PM}）"

did=0
case "$PM" in
  apt)  remove_apt      && did=1 || true ;;
  dnf)  remove_rpm dnf  && did=1 || true ;;
  yum)  remove_rpm yum  && did=1 || true ;;
  brew) remove_brew     && did=1 || true ;;
esac

# ---- 结果 ------------------------------------------------------------------
if [ "$did" -eq 1 ]; then
  log "Python ${PY_SERIES} 卸载动作已完成"
else
  warn "未执行卸载：未匹配到目标包"
fi

resolve_python
if [ -n "${PY_BIN:-}" ]; then
  warn "PATH 中仍存在 ${PY_BIN}：$(command -v "$PY_BIN")，可能来自其他安装方式（pyenv/源码等）"
fi
