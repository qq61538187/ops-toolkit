#!/usr/bin/env bash
#
# mihomo (Clash.Meta) 卸载脚本
# 精确反向清理 install.sh 的行为:停止/禁用服务、删除 systemd 单元、
# 删除二进制、删除配置目录。路径/变量与 install.sh 保持一致。
#
set -euo pipefail

# ---- 与 install.sh 完全一致的固定配置 --------------------------------------
BIN_PATH="/usr/local/bin/mihomo"
CONF_DIR="/etc/mihomo"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
# ---------------------------------------------------------------------------

log()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行(sudo bash uninstall.sh)"

# ---- 停止并禁用服务 --------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files 2>/dev/null | grep -q '^mihomo\.service'; then
    log "停止并禁用 mihomo 服务"
    systemctl stop mihomo >/dev/null 2>&1 || true
    systemctl disable mihomo >/dev/null 2>&1 || true
  fi
fi

# ---- 删除 systemd 单元 -----------------------------------------------------
if [ -f "$SERVICE_FILE" ]; then
  log "删除 ${SERVICE_FILE}"
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload || true
  systemctl reset-failed mihomo >/dev/null 2>&1 || true
fi

# ---- 删除二进制 ------------------------------------------------------------
if [ -f "$BIN_PATH" ]; then
  log "删除二进制 ${BIN_PATH}"
  rm -f "$BIN_PATH"
fi

# ---- 删除配置目录 ----------------------------------------------------------
# 仅删除本脚本创建的目录 /etc/mihomo(含订阅缓存 providers/)
if [ -d "$CONF_DIR" ]; then
  log "删除配置目录 ${CONF_DIR}"
  rm -rf "$CONF_DIR"
fi

log "✅ mihomo 已彻底卸载"
