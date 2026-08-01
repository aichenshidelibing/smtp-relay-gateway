#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SMTP Relay Gateway 卸载脚本
# ============================================================

SCRIPT_NAME="$(basename "$0")"

log() {
  printf '\n\033[1;34m>>> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2
}

fail() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || fail "请使用 root 运行：sudo bash ${SCRIPT_NAME}"
}

read_default() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "${prompt} [${default}]: " value
  printf '%s' "${value:-$default}"
}

confirm() {
  local prompt="$1"
  local default="${2:-no}"
  local value=""
  value="$(read_default "$prompt" "$default")"
  [[ "$value" =~ ^[Yy] ]]
}

# ============================================================
# 备份恢复
# ============================================================

find_latest_backup() {
  local config="$1"
  local dir
  dir=$(dirname "$config")
  local base
  base=$(basename "$config")

  # 查找最新的备份文件
  local latest
  latest=$(ls -t "${dir}/${base}".bak.* 2>/dev/null | head -1)

  if [[ -n "$latest" && -f "$latest" ]]; then
    printf '%s' "$latest"
    return 0
  fi
  return 1
}

# ============================================================
# 主卸载函数
# ============================================================

uninstall() {
  need_root

  echo "============================================================"
  echo "SMTP Relay Gateway 卸载程序"
  echo "============================================================"
  echo
  echo "此脚本将完全移除："
  echo "  - Postfix 配置备份恢复"
  echo "  - SASL 认证用户"
  echo "  - 上游 SMTP 密码文件"
  echo "  - TLS 证书目录"
  echo "  - UFW 防火墙规则"
  echo

  if ! confirm "确认卸载？此操作不可逆！输入 yes 继续" "no"; then
    echo "已取消卸载。"
    exit 0
  fi

  # ----------------------------------------------------------
  log "停止 Postfix 服务"
  # ----------------------------------------------------------
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop postfix 2>/dev/null || true
    systemctl disable postfix 2>/dev/null || true
    echo "  Postfix 已停止并禁用"
  elif command -v service >/dev/null 2>&1; then
    service postfix stop 2>/dev/null || true
    echo "  Postfix 已停止"
  fi

  # ----------------------------------------------------------
  log "检查备份文件"
  # ----------------------------------------------------------
  local main_backup
  local master_backup

  main_backup=$(find_latest_backup "/etc/postfix/main.cf")
  if [[ -n "$main_backup" ]]; then
    echo "  找到 Postfix main.cf 备份: ${main_backup}"
  fi

  master_backup=$(find_latest_backup "/etc/postfix/master.cf")
  if [[ -n "$master_backup" ]]; then
    echo "  找到 Postfix master.cf 备份: ${master_backup}"
  fi

  # ----------------------------------------------------------
  log "恢复 Postfix 配置（可选）"
  # ----------------------------------------------------------
  if confirm "是否恢复原始 Postfix 配置？输入 y 恢复，n 仅清理本项目配置" "n"; then
    if [[ -n "$main_backup" ]]; then
      cp -a "$main_backup" /etc/postfix/main.cf
      echo "  已恢复 main.cf"
    else
      echo "  未找到 main.cf 备份，跳过"
    fi

    if [[ -n "$master_backup" ]]; then
      cp -a "$master_backup" /etc/postfix/master.cf
      echo "  已恢复 master.cf"
    else
      echo "  未找到 master.cf 备份，跳过"
    fi

    # 清理本项目添加的配置块
    if grep -q "# BEGIN MANAGED SMTP RELAY" /etc/postfix/master.cf 2>/dev/null; then
      python3 - "/etc/postfix/master.cf" "# BEGIN MANAGED SMTP RELAY" "# END MANAGED SMTP RELAY" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
begin = sys.argv[2]
end = sys.argv[3]
text = path.read_text()
lines = text.splitlines(True)
out = []
skip = False
for line in lines:
    if line.rstrip('\n') == begin:
        skip = True
        continue
    if skip and line.rstrip('\n') == end:
        skip = False
        continue
    if not skip:
        out.append(line)
path.write_text(''.join(out))
PY
      echo "  已清理 master.cf 中的托管配置块"
    fi
  else
    echo "  跳过恢复，将清理托管配置"
    # 仅清理托管配置块
    if grep -q "# BEGIN MANAGED SMTP RELAY" /etc/postfix/master.cf 2>/dev/null; then
      python3 - "/etc/postfix/master.cf" "# BEGIN MANAGED SMTP RELAY" "# END MANAGED SMTP RELAY" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
begin = sys.argv[2]
end = sys.argv[3]
text = path.read_text()
lines = text.splitlines(True)
out = []
skip = False
for line in lines:
    if line.rstrip('\n') == begin:
        skip = True
        continue
    if skip and line.rstrip('\n') == end:
        skip = False
        continue
    if not skip:
        out.append(line)
path.write_text(''.join(out))
PY
      echo "  已清理 master.cf 中的托管配置块"
    fi
  fi

  # ----------------------------------------------------------
  log "删除 SASL 认证用户"
  # ----------------------------------------------------------
  echo "  当前 SASL 用户："
  if sasldblistusers2 2>/dev/null | grep -q '@'; then
    sasldblistusers2 2>/dev/null | grep '@' | while read line; do
      local user
      user=$(echo "$line" | cut -d: -f1)
      echo "    删除用户: $user"
      saslpasswd2 -d "$user" 2>/dev/null || true
    done
  else
    echo "    （无 SASL 用户）"
  fi

  # ----------------------------------------------------------
  log "删除上游 SMTP 密码文件"
  # ----------------------------------------------------------
  if [[ -f /etc/postfix/sasl_passwd ]]; then
    rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
    echo "  已删除 sasl_passwd 和 sasl_passwd.db"
  else
    echo "  sasl_passwd 文件不存在，跳过"
  fi

  # ----------------------------------------------------------
  log "删除 SASL 配置目录"
  # ----------------------------------------------------------
  if [[ -d /etc/postfix/sasl ]]; then
    rm -rf /etc/postfix/sasl
    echo "  已删除 /etc/postfix/sasl"
  else
    echo "  /etc/postfix/sasl 目录不存在，跳过"
  fi

  # ----------------------------------------------------------
  log "删除 TLS 证书目录（可选）"
  # ----------------------------------------------------------
  if [[ -d /etc/postfix/certs ]]; then
    if confirm "是否删除 TLS 证书目录 /etc/postfix/certs？" "n"; then
      rm -rf /etc/postfix/certs
      echo "  已删除 /etc/postfix/certs"
    else
      echo "  保留证书目录"
    fi
  else
    echo "  /etc/postfix/certs 目录不存在，跳过"
  fi

  # ----------------------------------------------------------
  log "清理 UFW 防火墙规则"
  # ----------------------------------------------------------
  if command -v ufw >/dev/null 2>&1; then
    echo "  尝试清理 UFW SMTP Relay 相关规则..."
    # 查找并删除包含 SMTP Relay 注释的规则
    local rules
    rules=$(ufw status numbered 2>/dev/null || true)
    if [[ -n "$rules" ]]; then
      echo "$rules" | grep -i "smtp\|2525\|relay" | while read -r line; do
        echo "    发现相关规则，可能需要手动清理: $line"
      done
      echo "  请手动使用 ufw delete NUM 删除相关规则"
    else
      echo "  无相关 UFW 规则"
    fi
  else
    echo "  未检测到 ufw，跳过"
  fi

  # ----------------------------------------------------------
  log "重启 Postfix"
  # ----------------------------------------------------------
  if command -v systemctl >/dev/null 2>&1; then
    if [[ -f /etc/postfix/main.cf ]]; then
      postfix check 2>/dev/null && systemctl restart postfix || true
      echo "  Postfix 已重启"
    fi
  elif command -v service >/dev/null 2>&1; then
    if [[ -f /etc/postfix/main.cf ]]; then
      postfix check 2>/dev/null && service postfix restart || true
      echo "  Postfix 已重启"
    fi
  fi

  # ----------------------------------------------------------
  log "卸载完成"
  # ----------------------------------------------------------
  cat <<'EOF'

============================================================
卸载完成
============================================================

已清理：
  - SASL 认证用户
  - 上游 SMTP 密码文件
  - SASL 配置
  - 托管配置块

如需完全卸载 Postfix，请运行：
  apt-get remove --purge postfix sasl2-bin
  apt-get autoremove

============================================================
EOF
}

uninstall "$@"
