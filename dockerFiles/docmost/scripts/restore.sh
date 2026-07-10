#!/usr/bin/env bash
#
# restore.sh — 从备份压缩包还原本 compose 组件的数据
#
# 通用脚本：放在 <组件>/scripts/ 下，自动定位组件目录，无需按组件改动。
#
# 用法：
#   ./restore.sh <备份zip路径>        # 例：./restore.sh ../backups/backup_20260710085630.zip
#   ./restore.sh -y <备份zip路径>     # 跳过确认
#
# 行为(还原是破坏性操作,会覆盖当前 volumes/):
#   1. 若有 docker/compose,先 `compose stop` 释放文件占用;
#   2. 还原前对当前 volumes/ + .env 做一份 pre-restore_<ts>.zip 安全快照(放 backups/),便于回退;
#   3. 清空并从压缩包还原 volumes/(及 .env,若包内含);
#   4. `compose up -d` 重新拉起容器。
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
log()  { printf '%s[restore]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[restore]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[restore]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  restore.sh <备份zip路径>       从指定备份还原(会覆盖当前 volumes/)
  restore.sh -y <备份zip路径>    跳过确认
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMP_DIR="$(dirname "$SCRIPT_DIR")"
COMP_NAME="$(basename "$COMP_DIR")"
BACKUP_DIR="$COMP_DIR/backups"

# ---- 解析参数 --------------------------------------------------------------
assume_yes=0
archive=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "未知选项:$1" ;;
    *) archive="$1"; shift ;;
  esac
done
[ -n "$archive" ] || { usage; exit 1; }
[ -f "$archive" ] || die "备份文件不存在:$archive"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

command -v unzip >/dev/null 2>&1 || die "未找到 unzip 命令(Debian: apt install unzip;RHEL: yum install unzip)。"
unzip -t -qq "$archive" >/dev/null 2>&1 || die "不是有效的 zip 压缩包:$archive"

# 包内是否含 volumes/(决定是否清空当前 volumes)
has_volumes=0
if unzip -Z1 "$archive" 2>/dev/null | grep -q '^volumes/'; then has_volumes=1; fi

# ---- 确认(破坏性)---------------------------------------------------------
printf '%s将用以下备份还原「%s」,当前 volumes/ 会被覆盖:%s\n' "$BOLD" "$COMP_NAME" "$RESET"
printf '  %s\n' "$archive"
if [ "$assume_yes" -ne 1 ]; then
  printf '确认还原?(还原前会自动生成一份 pre-restore 安全快照)[y/N] '
  read -r ans || ans=""
  case "$ans" in y|Y|yes|YES) ;; *) warn "已取消"; exit 0 ;; esac
fi

# ---- 探测 compose ----------------------------------------------------------
COMPOSE=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"; fi
fi

# ---- 停止容器,释放文件占用 ------------------------------------------------
if [ -n "$COMPOSE" ]; then
  log "停止容器…"
  ( cd "$COMP_DIR" && $COMPOSE stop ) || warn "停止容器失败,继续还原(可能因文件占用失败)"
else
  warn "未检测到 docker/compose,仅还原文件,请稍后手动拉起容器"
fi

# ---- 还原前安全快照 --------------------------------------------------------
if [ -d "$COMP_DIR/volumes" ] || [ -f "$COMP_DIR/.env" ]; then
  if command -v zip >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR"
    ts="$(date +%Y%m%d%H%M%S)"
    safety="$BACKUP_DIR/pre-restore_${ts}.zip"
    snap=()
    [ -d "$COMP_DIR/volumes" ] && snap+=("volumes")
    [ -f "$COMP_DIR/.env" ]    && snap+=(".env")
    ( cd "$COMP_DIR" && zip -r -q "$safety" "${snap[@]}" -x 'backups/*' ) \
      && log "已生成安全快照:backups/pre-restore_${ts}.zip"
  else
    warn "未找到 zip,跳过安全快照(还原后将无法回退到还原前状态)"
  fi
fi

# ---- 还原 ------------------------------------------------------------------
if [ "$has_volumes" -eq 1 ] && [ -d "$COMP_DIR/volumes" ]; then
  log "清空当前 volumes/…"
  rm -rf "$COMP_DIR/volumes"
fi
log "从备份解压还原…"
unzip -o -q "$archive" -d "$COMP_DIR"

# ---- 重新拉起 --------------------------------------------------------------
if [ -n "$COMPOSE" ]; then
  log "拉起容器…"
  ( cd "$COMP_DIR" && $COMPOSE up -d ) || warn "拉起容器失败,请手动检查:$COMPOSE up -d"
fi

log "完成:已从 $(basename "$archive") 还原「${COMP_NAME}」"
