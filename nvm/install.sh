#!/usr/bin/env bash
#
# install.sh — 安装 nvm（Node Version Manager，默认最新发布版）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 请改用 nvm-windows，见文末提示）
#
# 说明：nvm 是「按用户」安装的工具，默认装到 $HOME/.nvm，并向 shell 配置
#       文件注入加载片段；本脚本不写入系统目录，无需 root/sudo。
#       默认解析并安装 nvm 的最新发布版；可用 NVM_VERSION 环境变量指定版本。
#
# 用法：
#   ./install.sh                       # 安装最新版 nvm 到 ~/.nvm
#   NVM_VERSION=0.40.5 ./install.sh    # 指定 nvm 版本
#   NVM_DIR=/opt/nvm ./install.sh      # 自定义安装目录
#   PROFILE=~/.zshrc ./install.sh      # 指定要写入的 shell 配置文件
#
set -euo pipefail

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NVM_REPO="https://github.com/nvm-sh/nvm.git"
NVM_API_LATEST="https://api.github.com/repos/nvm-sh/nvm/releases/latest"
NVM_VERSION_FALLBACK="0.40.5"          # 无法联网解析最新版时的兜底版本
NVM_VERSION="${NVM_VERSION:-}"         # 默认空→解析最新发布版；可用环境变量显式覆盖
# NVM_TAG / NVM_TARBALL_URL 在 resolve_version() 里按最终版本推导

# 注入 shell 配置文件时使用的标记，卸载脚本据此精确移除（务必与 uninstall.sh 一致）
BLOCK_BEGIN="# >>> nvm (ops-toolkit) >>>"
BLOCK_END="# <<< nvm (ops-toolkit) <<<"

log()  { printf '\033[0;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# nvm 按用户安装，不应以 root 运行（会把 ~/.nvm 装到 root 家目录）
if [ "$(id -u)" -eq 0 ] && [ -z "${ALLOW_ROOT:-}" ]; then
  warn "检测到以 root 运行：nvm 将安装到 root 用户的家目录。"
  warn "若确需如此请设置 ALLOW_ROOT=1 重试；否则请以目标普通用户身份运行。"
  die  "已中止。"
fi

# ---- 探测操作系统 ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。nvm-sh 不支持 Windows，请改用 nvm-windows：
         https://github.com/coreybutler/nvm-windows/releases" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

# ---- 下载工具（与 node/install.sh 保持一致）-------------------------------
download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    die "未找到 curl 或 wget，无法下载"
  fi
}

# ---- 解析要安装的 nvm 版本（默认取最新发布版）------------------------------
resolve_version() {
  if [ -n "$NVM_VERSION" ]; then
    log "使用指定版本：nvm ${NVM_VERSION}"
  else
    local tag=""
    if command -v curl >/dev/null 2>&1; then
      tag="$(curl -fsSL "$NVM_API_LATEST" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[^"]*"v?([^"]+)".*/\1/')"
    elif command -v wget >/dev/null 2>&1; then
      tag="$(wget -qO- "$NVM_API_LATEST" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[^"]*"v?([^"]+)".*/\1/')"
    fi
    if [ -n "$tag" ]; then
      NVM_VERSION="$tag"
      log "解析到 nvm 最新发布版：${NVM_VERSION}"
    else
      NVM_VERSION="$NVM_VERSION_FALLBACK"
      warn "无法获取最新版本（网络受限?），回退到已知稳定版：${NVM_VERSION}"
    fi
  fi
  NVM_TAG="v${NVM_VERSION}"
  NVM_TARBALL_URL="https://github.com/nvm-sh/nvm/archive/refs/tags/${NVM_TAG}.tar.gz"
}

# ---- 读取当前已加载的 nvm 版本（在子 shell 内 source，避免污染本脚本）------
current_version() {
  [ -s "$NVM_DIR/nvm.sh" ] || return 0
  ( set +eu
    unset npm_config_prefix 2>/dev/null || true
    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh" >/dev/null 2>&1
    nvm --version 2>/dev/null
  ) || true
}

# ---- 选择要写入的 shell 配置文件 ------------------------------------------
detect_profiles() {
  if [ -n "${PROFILE:-}" ]; then
    printf '%s\n' "$PROFILE"
    return
  fi
  case "$(basename "${SHELL:-}")" in
    zsh)
      printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc"
      ;;
    bash)
      if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.bash_profile" ]; then
        [ -f "$HOME/.bashrc" ]       && printf '%s\n' "$HOME/.bashrc"
        [ -f "$HOME/.bash_profile" ] && printf '%s\n' "$HOME/.bash_profile"
      elif [ "$OS" = "darwin" ]; then
        printf '%s\n' "$HOME/.bash_profile"   # macOS 登录 shell 默认读取
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

# ---- 向配置文件写入加载片段（幂等）----------------------------------------
write_profile_block() {
  local profile="$1"
  mkdir -p "$(dirname "$profile")"
  [ -e "$profile" ] || : > "$profile"
  if grep -qF "$BLOCK_BEGIN" "$profile" 2>/dev/null; then
    log "加载片段已存在，跳过：${profile}"
    return
  fi
  {
    printf '\n%s\n' "$BLOCK_BEGIN"
    printf 'export NVM_DIR="%s"\n' "$NVM_DIR"
    printf '%s\n' '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    printf '%s\n' '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    printf '%s\n' "$BLOCK_END"
  } >> "$profile"
  log "已写入加载片段：${profile}"
}

# ---- 安装方式：git（可 nvm upgrade）优先，否则回退发布包 -------------------
install_via_git() {
  command -v git >/dev/null 2>&1 || return 1
  if [ -d "$NVM_DIR/.git" ]; then
    log "检测到已有 git 仓库，切换到 ${NVM_TAG}"
    git -C "$NVM_DIR" fetch --tags --depth 1 origin "$NVM_TAG" >/dev/null 2>&1 \
      || git -C "$NVM_DIR" fetch --tags origin >/dev/null 2>&1 \
      || return 1
    git -C "$NVM_DIR" checkout -q "$NVM_TAG" || return 1
    return 0
  fi
  # 仅当目录不存在或为空时才 clone，避免 clone 失败或覆盖已装内容
  if [ ! -e "$NVM_DIR" ] || [ -z "$(ls -A "$NVM_DIR" 2>/dev/null)" ]; then
    log "使用 git 克隆 ${NVM_TAG} 到 ${NVM_DIR}"
    mkdir -p "$NVM_DIR"
    git clone -q --branch "$NVM_TAG" --depth 1 "$NVM_REPO" "$NVM_DIR" || return 1
    return 0
  fi
  return 1
}

install_via_tarball() {
  local tarball="${TMP_DIR}/nvm.tar.gz"
  log "下载发布包：${NVM_TARBALL_URL}"
  download "$NVM_TARBALL_URL" "$tarball"
  log "解压 ..."
  tar -xzf "$tarball" -C "$TMP_DIR"
  local src="${TMP_DIR}/nvm-${NVM_VERSION}"
  [ -d "$src" ] || die "解压结果异常：未找到 ${src}"
  mkdir -p "$NVM_DIR"
  # 覆盖式拷贝 nvm 自身文件，保留 $NVM_DIR/versions 等已安装的 node 版本
  log "安装文件到 ${NVM_DIR}（保留已存在的 node 版本）"
  ( cd "$src" && tar -cf - . ) | ( cd "$NVM_DIR" && tar -xf - )
}

# ---- 主流程 ----------------------------------------------------------------
detect_os

# 运行时（nvm install <node>）需要 curl 或 wget
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  warn "系统缺少 curl / wget，nvm 后续下载 Node.js 时将无法工作，建议先安装其一"
fi

# 确定要安装的版本（默认最新发布版）
resolve_version

# 已安装同版本则仅确保配置写好后退出
if [ "$(current_version)" = "$NVM_VERSION" ]; then
  log "nvm ${NVM_VERSION} 已安装于 ${NVM_DIR}"
  while IFS= read -r p; do [ -n "$p" ] && write_profile_block "$p"; done < <(detect_profiles)
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log "目标：nvm ${NVM_VERSION} -> ${NVM_DIR}"
if install_via_git; then
  log "已通过 git 安装"
else
  install_via_tarball
fi

# 写入 shell 配置
while IFS= read -r p; do [ -n "$p" ] && write_profile_block "$p"; done < <(detect_profiles)

# ---- 验证 ------------------------------------------------------------------
ver="$(current_version)"
if [ -n "$ver" ]; then
  log "安装完成：nvm ${ver}（NVM_DIR=${NVM_DIR}）"
  warn "在当前终端启用 nvm：source \"${NVM_DIR}/nvm.sh\"（或重新打开终端）"
  log  "之后可执行： nvm install --lts   安装最新 LTS 版 Node.js"
else
  die "安装后无法加载 nvm（缺少 ${NVM_DIR}/nvm.sh）"
fi
