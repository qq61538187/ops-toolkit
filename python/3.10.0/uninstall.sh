#!/usr/bin/env bash
#
# uninstall.sh — 卸载 Python 3.10（对应 install.sh 的系统包管理器安装）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请用 winget uninstall / 控制面板）
#
# 安全须知：许多 Linux 发行版把「系统自带的 python3」作为核心依赖，强行卸载
#           可能连带移除桌面环境/包管理器等组件。因此本脚本：
#           - 默认只卸载「精确解释器包」python3.10（deadsnakes 场景），不动系统 python3；
#           - 若要卸载发行版默认 python3，必须显式设置 FORCE_SYSTEM=1，风险自负。
#
# 用法：
#   ./uninstall.sh                    # 卸载 python3.10 系列包（若存在）
#   REMOVE_PPA=1 ./uninstall.sh       # 连同 deadsnakes PPA 一起移除
#   FORCE_SYSTEM=1 ./uninstall.sh     # 【危险】卸载发行版默认 python3
#
set -euo pipefail

PY_VERSION="3.10.0"
PY_SERIES="${PY_VERSION%.*}"          # -> 3.10

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 探测（与 install.sh 一致）--------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 winget uninstall 或控制面板卸载。" ;;
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

# ---- 各包管理器的卸载动作 --------------------------------------------------
remove_apt() {
  export DEBIAN_FRONTEND=noninteractive
  local pkgs=()
  # 优先卸载精确系列包
  if dpkg -l "python${PY_SERIES}" >/dev/null 2>&1; then
    pkgs+=("python${PY_SERIES}" "python${PY_SERIES}-venv" "python${PY_SERIES}-dev")
  fi
  if [ -n "${FORCE_SYSTEM:-}" ]; then
    warn "FORCE_SYSTEM=1：将卸载发行版默认 python3（高风险）"
    pkgs+=(python3 python3-pip python3-venv python3-dev)
  fi
  if [ "${#pkgs[@]}" -eq 0 ]; then
    warn "未发现 python${PY_SERIES} 系列包；如需卸载系统默认 python3 请加 FORCE_SYSTEM=1"
    return 1
  fi
  log "apt-get remove: ${pkgs[*]}"
  $SUDO apt-get remove -y "${pkgs[@]}" 2>/dev/null || true
  $SUDO apt-get autoremove -y || true
  if [ -n "${REMOVE_PPA:-}" ] && command -v add-apt-repository >/dev/null 2>&1; then
    log "移除 deadsnakes PPA ..."
    $SUDO add-apt-repository -y --remove ppa:deadsnakes/ppa || warn "移除 PPA 失败（可能未添加）"
    $SUDO apt-get update -y || true
  fi
  return 0
}

remove_rpm() {
  local mgr="$1"
  if rpm -q "python${PY_SERIES}" >/dev/null 2>&1; then
    log "${mgr} remove python${PY_SERIES} ..."
    $SUDO "$mgr" remove -y "python${PY_SERIES}" || true
    return 0
  fi
  if [ -n "${FORCE_SYSTEM:-}" ]; then
    warn "FORCE_SYSTEM=1：${mgr} remove python3（高风险）"
    $SUDO "$mgr" remove -y python3 || true
    return 0
  fi
  warn "未发现 python${PY_SERIES} 包；如需卸载系统默认 python3 请加 FORCE_SYSTEM=1"
  return 1
}

remove_brew() {
  if brew list --formula "python@${PY_SERIES}" >/dev/null 2>&1; then
    log "brew uninstall python@${PY_SERIES} ..."
    brew uninstall "python@${PY_SERIES}"
    return 0
  fi
  warn "Homebrew 未安装 python@${PY_SERIES}，跳过（不动系统/其它 python）"
  return 1
}

# ---- 主流程 ----------------------------------------------------------------
detect_os
detect_pm
setup_privilege

log "准备卸载 Python ${PY_SERIES} 系列（经由 ${PM}）"

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

if command -v "python${PY_SERIES}" >/dev/null 2>&1; then
  warn "PATH 中仍存在 python${PY_SERIES}：$(command -v "python${PY_SERIES}")，可能来自其他安装方式"
fi
