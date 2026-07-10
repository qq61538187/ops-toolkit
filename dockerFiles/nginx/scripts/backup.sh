#!/usr/bin/env bash
#
# backup.sh — 备份本 compose 组件的数据
#
# 通用脚本：放在 <组件>/scripts/ 下，自动定位组件目录，无需按组件改动。
#
# 备份对象：组件目录下的 volumes/(数据)与 .env(配置，若存在)。
# 输出：组件目录下 backups/backup_<YYYYMMDDHHMMSS>.zip(与 scripts/ 同级)。
#
# 一致性策略：备份前若容器在运行，先 `compose stop` 做冷备(避免数据库等热备损坏)，
#             备份完成后恢复其原运行状态(原来在跑的再 `compose start` 拉起)。
#             未安装 docker/compose 时退化为热备并给出告警。
#
# 用法：
#   ./backup.sh
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
log()  { printf '%s[backup]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[backup]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[backup]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMP_DIR="$(dirname "$SCRIPT_DIR")"
COMP_NAME="$(basename "$COMP_DIR")"
BACKUP_DIR="$COMP_DIR/backups"

command -v zip >/dev/null 2>&1 || die "未找到 zip 命令(Debian: apt install zip;RHEL: yum install zip)。"

# ---- 组装备份对象(相对 COMP_DIR)------------------------------------------
targets=()
[ -d "$COMP_DIR/volumes" ] && targets+=("volumes")
[ -f "$COMP_DIR/.env" ]    && targets+=(".env")
[ "${#targets[@]}" -gt 0 ] || die "组件目录无 volumes/ 或 .env 可备份:$COMP_DIR"

# ---- 探测 compose(用于冷备)-----------------------------------------------
COMPOSE=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"; fi
fi

# ---- 一致性:运行中则先停,备份后恢复 --------------------------------------
was_running=0
if [ -n "$COMPOSE" ]; then
  if [ -n "$(cd "$COMP_DIR" && $COMPOSE ps -q 2>/dev/null || true)" ]; then
    was_running=1
    log "检测到容器在运行,停止以做一致性冷备…"
    ( cd "$COMP_DIR" && $COMPOSE stop ) || warn "停止容器失败,继续做热备(数据可能不一致)"
  fi
else
  warn "未检测到 docker/compose,执行热备(无法保证数据一致性)"
fi

mkdir -p "$BACKUP_DIR"
ts="$(date +%Y%m%d%H%M%S)"
out="$BACKUP_DIR/backup_${ts}.zip"

log "打包 ${COMP_NAME}: ${targets[*]} -> backups/backup_${ts}.zip"
( cd "$COMP_DIR" && zip -r -q "$out" "${targets[@]}" -x 'backups/*' )

if [ "$was_running" -eq 1 ]; then
  log "备份完成,恢复容器运行状态…"
  ( cd "$COMP_DIR" && $COMPOSE start ) || warn "恢复容器运行失败,请手动检查:$COMPOSE up -d"
fi

log "完成:$out ($(du -h "$out" | cut -f1))"
