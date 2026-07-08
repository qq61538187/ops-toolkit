#!/usr/bin/env bash
#
# 开启代理:启动(并设为开机自启)mihomo 服务,做一次连通性自检。
# 前提:已先执行 ./install.sh 完成安装。
#
set -euo pipefail

# ---- 与 install.sh 一致的固定配置 ------------------------------------------
BIN_PATH="/usr/local/bin/mihomo"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
CTRL_ADDR="127.0.0.1:9090"
HTTP_PORT=7890
SOCKS_PORT=7891
# ---------------------------------------------------------------------------

log()  { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行(sudo ./start.sh)"
[ -x "$BIN_PATH" ]     || die "未检测到 mihomo,请先执行 ./install.sh"
[ -f "$SERVICE_FILE" ] || die "未检测到 systemd 单元,请先执行 ./install.sh"

# ---- 启动 ------------------------------------------------------------------
log "开启代理(启动 mihomo 服务并设为开机自启)..."
systemctl enable mihomo >/dev/null 2>&1 || true
systemctl restart mihomo

# 等待服务就绪(最多 5 秒)
for _ in 1 2 3 4 5; do
  systemctl is-active --quiet mihomo && break
  sleep 1
done
if ! systemctl is-active --quiet mihomo; then
  warn "服务未正常运行,查看日志:journalctl -u mihomo -n 50 --no-pager"
  die "启动失败"
fi
log "服务已运行"

# ---- 连通性自检(非致命)---------------------------------------------------
log "代理连通性自检(节点可能需要几秒预热)..."
ok=0
for _ in 1 2 3 4 5 6; do
  if curl -fsS -m 10 -x "http://127.0.0.1:${HTTP_PORT}" \
       https://www.gstatic.com/generate_204 -o /dev/null 2>/dev/null; then
    ok=1; break
  fi
  sleep 2
done
if [ "$ok" = 1 ]; then
  log "✅ 代理可用,已能访问外网"
else
  warn "自检未通过(节点未就绪或订阅无效),稍后手动重试:"
  warn "  curl -x http://127.0.0.1:${HTTP_PORT} https://www.google.com -I"
fi

cat <<EOF

============================================================
 代理已开启 ✅
------------------------------------------------------------
 HTTP  代理: http://127.0.0.1:${HTTP_PORT}
 SOCKS5 代理: socks5://127.0.0.1:${SOCKS_PORT}
 控制接口  : http://${CTRL_ADDR}

 让当前 shell 里的程序走代理:
   export https_proxy=http://127.0.0.1:${HTTP_PORT}
   export http_proxy=http://127.0.0.1:${HTTP_PORT}
   export all_proxy=socks5://127.0.0.1:${SOCKS_PORT}

 单条命令走代理:
   curl -x http://127.0.0.1:${HTTP_PORT} https://www.google.com

 关闭代理: ./close.sh
============================================================
EOF
