#!/usr/bin/env bash
#
# 关闭代理:停止 mihomo 服务并取消开机自启。
# 只停运行,不卸载(二进制/配置保留,随时可 ./start.sh 再开启)。
#
set -euo pipefail

SERVICE_FILE="/etc/systemd/system/mihomo.service"

log()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行(sudo ./close.sh)"

if [ ! -f "$SERVICE_FILE" ]; then
  warn "未检测到 mihomo 服务单元,可能尚未安装,无需关闭"
  exit 0
fi

log "关闭代理(停止服务并取消开机自启)..."
systemctl stop mihomo    >/dev/null 2>&1 || true
systemctl disable mihomo >/dev/null 2>&1 || true

if systemctl is-active --quiet mihomo; then
  die "服务仍在运行,请检查:systemctl status mihomo"
fi

log "✅ 代理已关闭(安装保留,重新开启:./start.sh)"

cat <<'EOF'

提示:如果你之前在 shell 里设过代理环境变量,记得清掉,
否则本终端的命令仍会尝试走已关闭的代理:
  unset http_proxy https_proxy all_proxy
EOF
