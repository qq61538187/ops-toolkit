#!/usr/bin/env bash
#
# 查看代理状态:服务运行情况 + 端口监听 + 直连/走代理的出口 IP 对比,
# 一眼确认到底有没有在翻墙。纯只读,不改任何状态,无需 root。
#
set -uo pipefail   # 不加 -e:各项检查即使失败也要继续往下走完

# ---- 与 install.sh 一致的固定配置 ------------------------------------------
BIN_PATH="/usr/local/bin/mihomo"
CONF_DIR="/etc/mihomo"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
HTTP_PORT=7890
SOCKS_PORT=7891
CTRL_ADDR="127.0.0.1:9090"
# ---------------------------------------------------------------------------

green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
ok()    { printf '  %s %s\n' "$(green ✔)" "$*"; }
no()    { printf '  %s %s\n' "$(red ✘)"  "$*"; }
warn()  { printf '  %s %s\n' "$(yellow ‣)" "$*"; }

echo "============================================================"
echo " mihomo 代理状态"
echo "============================================================"

# ---- 1. 安装情况 -----------------------------------------------------------
echo "[安装]"
[ -x "$BIN_PATH" ]           && ok "二进制 ${BIN_PATH}"        || no "二进制缺失(未安装?先 ./install.sh)"
[ -f "${CONF_DIR}/config.yaml" ] && ok "配置 ${CONF_DIR}/config.yaml" || no "配置缺失"
[ -f "$SERVICE_FILE" ]       && ok "服务单元 ${SERVICE_FILE}"   || no "服务单元缺失"

# ---- 2. 服务运行状态 -------------------------------------------------------
echo "[服务]"
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet mihomo; then
    ok "运行中(active)"
  else
    no "未运行(开启:./start.sh)"
  fi
  if systemctl is-enabled --quiet mihomo 2>/dev/null; then
    ok "开机自启:已启用"
  else
    warn "开机自启:未启用"
  fi
else
  warn "无 systemctl,跳过服务检查"
fi

# ---- 3. 端口监听 -----------------------------------------------------------
echo "[端口]"
port_listen() {  # $1=端口  返回 0 表示有进程在听
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":$1 "
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -q ":$1 "
  else
    return 2   # 无工具,无法判断
  fi
}
for p in "$HTTP_PORT:HTTP" "$SOCKS_PORT:SOCKS5" "${CTRL_ADDR##*:}:控制接口"; do
  num="${p%%:*}"; name="${p##*:}"
  port_listen "$num"; rc=$?
  case $rc in
    0) ok  "${name} 端口 ${num} 监听中" ;;
    2) warn "无 ss/netstat,无法检查端口 ${num}" ;;
    *) no  "${name} 端口 ${num} 未监听" ;;
  esac
done

# ---- 4. 出口 IP 对比 -------------------------------------------------------
echo "[出口 IP]"
if ! command -v curl >/dev/null 2>&1; then
  warn "无 curl,跳过出口 IP 检查"
else
  IP_API="https://api.ip.sb/geoip"        # 返回含 ip / country 的 JSON
  parse() { printf '%s' "$1" | grep -oE '"(ip|country)":"[^"]*"' | sed -E 's/"[a-z]+":"?([^"]*)"?/\1/' | paste -sd' ' -; }

  direct="$(curl -fsS -m 8 "$IP_API" 2>/dev/null || true)"
  proxied="$(curl -fsS -m 12 -x "http://127.0.0.1:${HTTP_PORT}" "$IP_API" 2>/dev/null || true)"

  d_ip="$(printf '%s' "$direct"  | grep -oE '"ip":"[^"]*"' | head -1 | sed -E 's/.*:"([^"]*)"/\1/')"
  p_ip="$(printf '%s' "$proxied" | grep -oE '"ip":"[^"]*"' | head -1 | sed -E 's/.*:"([^"]*)"/\1/')"

  [ -n "$d_ip" ] && printf '  直连出口 : %s\n' "$d_ip"        || warn "直连出口 : 获取失败"
  if [ -n "$p_ip" ]; then
    printf '  代理出口 : %s\n' "$p_ip"
    if [ -n "$d_ip" ] && [ "$d_ip" != "$p_ip" ]; then
      ok "出口 IP 已改变 → 代理生效,正在翻墙 🎉"
    elif [ -n "$d_ip" ] && [ "$d_ip" = "$p_ip" ]; then
      no "代理出口与直连相同 → 可能没走代理(节点未就绪/规则直连?)"
    fi
  else
    no "代理出口 : 获取失败(服务没开?节点无效?先 ./start.sh)"
  fi
fi

echo "============================================================"
