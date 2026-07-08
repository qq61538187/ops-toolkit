#!/usr/bin/env bash
#
# uninstall.sh — 卸载 nvm（对应 install.sh 的按用户安装，与版本无关）
#
# 支持系统：Ubuntu / Debian / Rocky Linux / CentOS / macOS
#           （Windows 的 nvm-windows 请用其自带卸载程序）
#
# 行为：移除 $NVM_DIR 目录，并从 shell 配置文件中删除本工具注入的加载片段。
#       注意：$NVM_DIR 下同时存放着由 nvm 安装的各 Node.js 版本，删除后一并移除。
#
# 用法：
#   ./uninstall.sh                     # 卸载 ~/.nvm（与安装默认一致）
#   NVM_DIR=/opt/nvm ./uninstall.sh    # 与安装时相同的自定义目录
#   PROFILE=~/.zshrc ./uninstall.sh    # 与安装时相同的配置文件
#   KEEP_NODE=1 ./uninstall.sh         # 仅移除 nvm 自身，保留已装的 node 版本
#
set -euo pipefail

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# 与 install.sh 完全一致的注入标记，用于精确移除
BLOCK_BEGIN="# >>> nvm (ops-toolkit) >>>"
BLOCK_END="# <<< nvm (ops-toolkit) <<<"

log()  { printf '\033[0;32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

# 与 install.sh 对称：默认不在 root 下操作普通用户目录
if [ "$(id -u)" -eq 0 ] && [ -z "${ALLOW_ROOT:-}" ]; then
  warn "检测到以 root 运行：将操作 root 用户家目录下的 nvm。"
  warn "若确需如此请设置 ALLOW_ROOT=1 重试；否则请以目标普通用户身份运行。"
  die  "已中止。"
fi

removed_any=0

# ---- 与 install.sh 相同的配置文件探测逻辑 ---------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "检测到 Windows。请使用 nvm-windows 自带卸载程序。" ;;
    *) die "不支持的操作系统：$(uname -s)" ;;
  esac
}

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
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

# ---- 从单个配置文件删除注入片段（仅删本工具标记之间的内容）-----------------
strip_profile_block() {
  local profile="$1"
  [ -f "$profile" ] || return 0
  grep -qF "$BLOCK_BEGIN" "$profile" 2>/dev/null || return 0

  local tmp
  tmp="$(mktemp)"
  # 删除 BLOCK_BEGIN ... BLOCK_END 之间（含标记）的所有行，并连同紧邻片段
  # 前、安装时注入的分隔空行一并去掉，使文件尽量还原为注入前的样子。
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    function flush(){ for (i=1;i<=n;i++) print buf[i]; n=0 }
    {
      if (skip)            { if (index($0,e)) skip=0; next }
      if (index($0,b))     { n=0; skip=1; next }   # 丢弃缓存的前置空行
      if (NF==0)           { buf[++n]=$0; next }   # 暂存空行，待确认后再输出
      flush(); print
    }
    END { flush() }
  ' "$profile" > "$tmp"

  # 用 cat 覆盖写回而非 mv，保留原文件的权限与 inode
  cat "$tmp" > "$profile"
  rm -f "$tmp"
  log "已从 ${profile} 移除 nvm 加载片段"
  removed_any=1
}

# ---- 主流程 ----------------------------------------------------------------
detect_os

# 1) 清理各 shell 配置文件
log "清理 shell 配置文件中的 nvm 加载片段 ..."
while IFS= read -r p; do
  [ -n "$p" ] && strip_profile_block "$p"
done < <(detect_profiles)

# 2) 移除 NVM_DIR
if [ -d "$NVM_DIR" ]; then
  if [ -n "${KEEP_NODE:-}" ] && [ -d "$NVM_DIR/versions" ]; then
    log "KEEP_NODE=1：保留已安装的 Node.js 版本，仅移除 nvm 自身文件"
    # 删除 nvm 自身文件，保留 versions/（已装 node）与 alias/ 等用户数据
    find "$NVM_DIR" -mindepth 1 -maxdepth 1 \
      ! -name versions ! -name alias -exec rm -rf {} + 2>/dev/null || true
    removed_any=1
    warn "已保留 ${NVM_DIR}/versions（其中的 node 需自行加入 PATH 或另行清理）"
  else
    log "删除 nvm 目录：${NVM_DIR}"
    warn "该目录同时包含由 nvm 安装的 Node.js 版本，将一并删除"
    rm -rf "${NVM_DIR:?}"
    removed_any=1
  fi
else
  warn "未找到 nvm 目录：${NVM_DIR}"
fi

# ---- 结果 ------------------------------------------------------------------
if [ "$removed_any" -eq 1 ]; then
  log "nvm 卸载完成"
  warn "当前终端可能仍加载着 nvm 函数，请重新打开终端，或执行： unset -f nvm 2>/dev/null; unset NVM_DIR"
else
  warn "未发现 nvm（NVM_DIR=${NVM_DIR}）的安装痕迹，无需卸载"
fi
