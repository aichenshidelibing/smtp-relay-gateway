#!/usr/bin/env bash
set -Eeuo pipefail

# Universal SMTP Relay installer for Debian/Ubuntu.
# This script configures Postfix as an authenticated SMTP relay on a custom port.

SCRIPT_NAME="$(basename "$0")"
MANAGED_BEGIN="# BEGIN MANAGED SMTP RELAY"
MANAGED_END="# END MANAGED SMTP RELAY"

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

need_debian_like() {
  command -v apt-get >/dev/null 2>&1 || fail "当前脚本只支持 Debian / Ubuntu 系统。"
}

read_default() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "${prompt} [${default}]: " value
  printf '%s' "${value:-$default}"
}

read_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "${prompt}: " value
    [[ -n "$value" ]] || echo "不能为空，请重新输入。"
  done
  printf '%s' "$value"
}

read_secret_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -s -p "${prompt}: " value
    printf '\n' >&2
    [[ -n "$value" ]] || echo "不能为空，请重新输入。" >&2
  done
  printf '%s' "$value"
}

confirm_secret() {
  local prompt="$1"
  local first=""
  local second=""
  while true; do
    first="$(read_secret_required "$prompt")"
    second="$(read_secret_required "请再次输入确认")"
    if [[ "$first" == "$second" ]]; then
      printf '%s' "$first"
      return 0
    fi
    echo "两次输入不一致，请重新输入。"
  done
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_cidrs() {
  local raw="$1"
  local result=""
  local item=""
  IFS=',' read -ra parts <<< "$raw"
  for item in "${parts[@]}"; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    if [[ "$item" != */* ]]; then
      item="${item}/32"
    fi
    if [[ -z "$result" ]]; then
      result="$item"
    else
      result="${result},${item}"
    fi
  done
  printf '%s' "$result"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || fail "端口必须是数字：${port}"
  (( port >= 1 && port <= 65535 )) || fail "端口范围必须是 1-65535：${port}"
}

is_valid_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

# ============================================================
# SMTP 连通性检测函数
# ============================================================

test_tcp_connectivity() {
  local host="$1"
  local port="$2"
  local timeout="${3:-10}"
  if timeout "$timeout" bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
    return 0
  fi
  return 1
}

test_smtp_starttls() {
  local host="$1"
  local port="$2"
  local timeout_sec="${3:-15}"
  timeout "$timeout_sec" bash -c "echo 'QUIT' | openssl s_client -connect '${host}:${port}' -starttls smtp -crlf 2>/dev/null" | grep -q "SSL handshake has read"
}

test_smtp_ssl() {
  local host="$1"
  local port="$2"
  local timeout_sec="${3:-15}"
  timeout "$timeout_sec" bash -c "echo 'QUIT' | openssl s_client -connect '${host}:${port}' 2>/dev/null" | grep -q "SSL handshake has read"
}

test_provider_connectivity() {
  local host="$1"
  local port="$2"
  local tls_mode="$3"
  local name="$4"

  if ! test_tcp_connectivity "$host" "$port" 8; then
    echo "  ${name}: ${host}:${port} - TCP 连接失败"
    return 1
  fi

  echo "  ${name}: ${host}:${port} - TCP 连接成功, 测试 TLS..."

  if [[ "$tls_mode" == "ssl" ]]; then
    if test_smtp_ssl "$host" "$port" 10; then
      echo "  ${name}: ${host}:${port} - TLS/SSL 连接成功 ✓"
      return 0
    fi
  else
    if test_smtp_starttls "$host" "$port" 10; then
      echo "  ${name}: ${host}:${port} - STARTTLS 连接成功 ✓"
      return 0
    fi
  fi

  echo "  ${name}: ${host}:${port} - TLS 连接失败"
  return 2
}

# ============================================================
# 服务商列表定义
# ============================================================

declare -A PROVIDER_HOSTS
declare -A PROVIDER_PORTS
declare -A PROVIDER_TLS
declare -A PROVIDER_NAMES

init_provider_list() {
  PROVIDER_HOSTS[1]="smtp.gmail.com"
  PROVIDER_PORTS[1]="587"
  PROVIDER_TLS[1]="starttls"
  PROVIDER_NAMES[1]="Gmail / Google Workspace"

  PROVIDER_HOSTS[2]="smtp-mail.outlook.com"
  PROVIDER_PORTS[2]="587"
  PROVIDER_TLS[2]="starttls"
  PROVIDER_NAMES[2]="Outlook / Hotmail"

  PROVIDER_HOSTS[3]="smtp.office365.com"
  PROVIDER_PORTS[3]="587"
  PROVIDER_TLS[3]="starttls"
  PROVIDER_NAMES[3]="Microsoft 365 / Office 365"

  PROVIDER_HOSTS[4]="smtp.mail.yahoo.com"
  PROVIDER_PORTS[4]="587"
  PROVIDER_TLS[4]="starttls"
  PROVIDER_NAMES[4]="Yahoo Mail"

  PROVIDER_HOSTS[5]="smtp.zoho.com"
  PROVIDER_PORTS[5]="587"
  PROVIDER_TLS[5]="starttls"
  PROVIDER_NAMES[5]="Zoho Mail"

  PROVIDER_HOSTS[6]="email-smtp.us-east-1.amazonaws.com"
  PROVIDER_PORTS[6]="587"
  PROVIDER_TLS[6]="starttls"
  PROVIDER_NAMES[6]="Amazon SES"

  PROVIDER_HOSTS[7]="smtp.sendgrid.net"
  PROVIDER_PORTS[7]="587"
  PROVIDER_TLS[7]="starttls"
  PROVIDER_NAMES[7]="SendGrid"

  PROVIDER_HOSTS[8]="smtp.mailgun.org"
  PROVIDER_PORTS[8]="587"
  PROVIDER_TLS[8]="starttls"
  PROVIDER_NAMES[8]="Mailgun"

  PROVIDER_HOSTS[9]="smtp.postmarkapp.com"
  PROVIDER_PORTS[9]="587"
  PROVIDER_TLS[9]="starttls"
  PROVIDER_NAMES[9]="Postmark"

  PROVIDER_HOSTS[10]="smtp.resend.com"
  PROVIDER_PORTS[10]="587"
  PROVIDER_TLS[10]="starttls"
  PROVIDER_NAMES[10]="Resend"

  PROVIDER_HOSTS[11]="live.smtp.mailtrap.io"
  PROVIDER_PORTS[11]="587"
  PROVIDER_TLS[11]="starttls"
  PROVIDER_NAMES[11]="Mailtrap"

  PROVIDER_HOSTS[12]="smtp.qq.com"
  PROVIDER_PORTS[12]="465"
  PROVIDER_TLS[12]="ssl"
  PROVIDER_NAMES[12]="QQ 邮箱"

  PROVIDER_HOSTS[13]="smtp.163.com"
  PROVIDER_PORTS[13]="465"
  PROVIDER_TLS[13]="ssl"
  PROVIDER_NAMES[13]="163/网易邮箱"
}

detect_available_providers() {
  log "正在检测服务商连通性（可能需要 2-3 分钟）..."
  echo

  init_provider_list

  declare -a available=()
  declare -a partial=()
  declare -a unavailable=()

  for i in {1..13}; do
    local host="${PROVIDER_HOSTS[$i]}"
    local port="${PROVIDER_PORTS[$i]}"
    local tls="${PROVIDER_TLS[$i]}"
    local name="${PROVIDER_NAMES[$i]}"

    printf "  [%2d/%2d] 检测 %-30s" "$i" "13" "$name"

    local result
    if test_provider_connectivity "$host" "$port" "$tls" "$name"; then
      available+=("$i")
      echo ""
    else
      local exit_code=$?
      if [[ $exit_code -eq 1 ]]; then
        unavailable+=("$i")
      else
        partial+=("$i")
      fi
      echo ""
    fi
  done

  echo
  log "检测完成！"

  if [[ ${#available[@]} -gt 0 ]]; then
    echo "可用的服务商 (${#available[@]} 个):"
    for idx in "${available[@]}"; do
      echo "  ${idx}) ${PROVIDER_NAMES[$idx]} - ${PROVIDER_HOSTS[$idx]}:${PROVIDER_PORTS[$idx]}"
    done
  fi

  if [[ ${#partial[@]} -gt 0 ]]; then
    echo
    echo "TCP 通但 TLS 失败的服务商:"
    for idx in "${partial[@]}"; do
      echo "  ${idx}) ${PROVIDER_NAMES[$idx]} - ${PROVIDER_HOSTS[$idx]}:${PROVIDER_PORTS[$idx]}"
    done
    echo "  (可能是防火墙阻止或服务商的 TLS 配置问题)"
  fi

  if [[ ${#unavailable[@]} -gt 0 ]]; then
    echo
    echo "不可达的服务商:"
    for idx in "${unavailable[@]}"; do
      echo "  ${idx}) ${PROVIDER_NAMES[$idx]} - ${PROVIDER_HOSTS[$idx]}:${PROVIDER_PORTS[$idx]}"
    done
  fi

  if [[ ${#available[@]} -eq 0 ]]; then
    warn "没有检测到可用的服务商，可能是网络问题。"
    echo "你可以选择 '14) 自定义 SMTP' 手动输入。"
  fi

  echo
  echo "可用服务商会优先显示，但仍可以选择其他服务商手动尝试。"

  printf '\n%s' "${available[@]}"
}

# ============================================================
# 上游账号验证（使用 Python smtplib）
# ============================================================

verify_upstream_credentials() {
  local host="$1"
  local port="$2"
  local user="$3"
  local pass="$4"
  local tls_mode="$5"
  local provider="$6"

  log "正在验证 ${provider} 上游账号..."
  echo "  提示: 如验证失败可跳过，不影响安装。"

  # 使用 Python smtplib 进行可靠验证
  python3 - "$host" "$port" "$user" "$pass" "$tls_mode" "$provider" <<'PYEOF'
import sys
import smtplib
import ssl
import socket

host = sys.argv[1]
port = int(sys.argv[2])
user = sys.argv[3]
password = sys.argv[4]
tls_mode = sys.argv[5]
provider = sys.argv[6]

def verify():
    try:
        if tls_mode == "ssl":
            # 隐式 TLS (端口 465)
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(host, port, context=context, timeout=20) as server:
                server.login(user, password)
                print("  账号认证成功 ✓")
                return True
        else:
            # STARTTLS (端口 587)
            with smtplib.SMTP(host, port, timeout=20) as server:
                server.ehlo()
                server.starttls(context=ssl.create_default_context())
                server.ehlo()
                server.login(user, password)
                print("  账号认证成功 ✓")
                return True
    except smtplib.SMTPAuthenticationError as e:
        print(f"  账号认证失败: 用户名或密码错误")
        print(f"  错误详情: {str(e)[:100]}")
        return False
    except smtplib.SMTPException as e:
        print(f"  SMTP 连接错误: {str(e)[:100]}")
        return False
    except socket.timeout:
        print(f"  连接超时，请检查网络和端口 {host}:{port}")
        return False
    except socket.error as e:
        print(f"  连接失败: {str(e)[:100]}")
        return False
    except Exception as e:
        print(f"  连接失败: {str(e)[:100]}")
        return False

if __name__ == "__main__":
    sys.exit(0 if verify() else 1)
PYEOF

  return $?
}

default_hostname() {
  hostname -f 2>/dev/null || hostname
}

backup_file() {
  local file="$1"
  local ts="$2"
  if [[ -f "$file" ]]; then
    cp -a "$file" "${file}.bak.${ts}"
  fi
}

remove_managed_block() {
  local file="$1"
  python3 - "$file" "$MANAGED_BEGIN" "$MANAGED_END" <<'PY'
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
}

select_provider() {
  echo
  echo "请选择上游 SMTP 服务商："
  echo "  0) 自动检测可用服务商（推荐）"
  echo "  1) Gmail / Google Workspace                 smtp.gmail.com:587 STARTTLS"
  echo "  2) Outlook / Hotmail 个人邮箱               smtp-mail.outlook.com:587 STARTTLS"
  echo "  3) Microsoft 365 / Office 365               smtp.office365.com:587 STARTTLS"
  echo "  4) Yahoo Mail                               smtp.mail.yahoo.com:587 STARTTLS"
  echo "  5) Zoho Mail                                smtp.zoho.com:587 STARTTLS"
  echo "  6) Amazon SES                               email-smtp.<region>.amazonaws.com:587 STARTTLS"
  echo "  7) SendGrid                                 smtp.sendgrid.net:587 STARTTLS"
  echo "  8) Mailgun                                  smtp.mailgun.org:587 STARTTLS"
  echo "  9) Postmark                                 smtp.postmarkapp.com:587 STARTTLS"
  echo " 10) Resend                                   smtp.resend.com:587 STARTTLS"
  echo " 11) Mailtrap                                 live.smtp.mailtrap.io:587 STARTTLS"
  echo " 12) QQ 邮箱                                  smtp.qq.com:465 SSL/TLS"
  echo " 13) 163/网易邮箱                             smtp.163.com:465 SSL/TLS"
  echo " 14) 自定义 SMTP"

  local choice=""
  choice="$(read_default "请选择" "0")"

  # 处理自动检测
  if [[ "$choice" == "0" ]]; then
    local available_list
    available_list=$(detect_available_providers)
    if [[ -n "$available_list" ]]; then
      echo
      echo "检测到的可用服务商列表如上。请输入数字选择 (1-14)："
      choice="$(read_default "请选择" "3")"
    else
      echo
      echo "未检测到可用服务商，请手动选择："
      choice="$(read_default "请选择" "3")"
    fi
  fi

  UPSTREAM_PROVIDER="自定义"
  UPSTREAM_HOST=""
  UPSTREAM_PORT="587"
  UPSTREAM_TLS_MODE="starttls"
  UPSTREAM_USER_HINT="SMTP 用户名/邮箱"
  UPSTREAM_PASSWORD_HINT="SMTP 密码、授权码、App Password 或 API Key"

  case "$choice" in
    1)
      UPSTREAM_PROVIDER="Gmail / Google Workspace"
      UPSTREAM_HOST="smtp.gmail.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Gmail/Google Workspace 邮箱"
      UPSTREAM_PASSWORD_HINT="Gmail App Password（建议开启 2FA 后创建）"
      ;;
    2)
      UPSTREAM_PROVIDER="Outlook / Hotmail 个人邮箱"
      UPSTREAM_HOST="smtp-mail.outlook.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Outlook/Hotmail 邮箱"
      UPSTREAM_PASSWORD_HINT="Outlook 密码或 App Password"
      ;;
    3)
      UPSTREAM_PROVIDER="Microsoft 365 / Office 365"
      UPSTREAM_HOST="smtp.office365.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Microsoft 365 邮箱"
      UPSTREAM_PASSWORD_HINT="Microsoft 365 密码或 App Password；需确认 SMTP AUTH 已启用"
      ;;
    4)
      UPSTREAM_PROVIDER="Yahoo Mail"
      UPSTREAM_HOST="smtp.mail.yahoo.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Yahoo 邮箱"
      UPSTREAM_PASSWORD_HINT="Yahoo App Password"
      ;;
    5)
      UPSTREAM_PROVIDER="Zoho Mail"
      UPSTREAM_HOST="smtp.zoho.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Zoho 邮箱"
      UPSTREAM_PASSWORD_HINT="Zoho 密码或 App Password"
      ;;
    6)
      UPSTREAM_PROVIDER="Amazon SES"
      local region=""
      region="$(read_default "Amazon SES region" "us-east-1")"
      UPSTREAM_HOST="email-smtp.${region}.amazonaws.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Amazon SES SMTP Username"
      UPSTREAM_PASSWORD_HINT="Amazon SES SMTP Password"
      ;;
    7)
      UPSTREAM_PROVIDER="SendGrid"
      UPSTREAM_HOST="smtp.sendgrid.net"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="SendGrid 用户名，通常填 apikey"
      UPSTREAM_PASSWORD_HINT="SendGrid API Key"
      ;;
    8)
      UPSTREAM_PROVIDER="Mailgun"
      UPSTREAM_HOST="smtp.mailgun.org"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Mailgun SMTP Login，例如 postmaster@mg.example.com"
      UPSTREAM_PASSWORD_HINT="Mailgun SMTP Password"
      ;;
    9)
      UPSTREAM_PROVIDER="Postmark"
      UPSTREAM_HOST="smtp.postmarkapp.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Postmark Server API Token"
      UPSTREAM_PASSWORD_HINT="Postmark Server API Token"
      ;;
    10)
      UPSTREAM_PROVIDER="Resend"
      UPSTREAM_HOST="smtp.resend.com"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Resend SMTP 用户名，通常填 resend"
      UPSTREAM_PASSWORD_HINT="Resend API Key"
      ;;
    11)
      UPSTREAM_PROVIDER="Mailtrap"
      UPSTREAM_HOST="live.smtp.mailtrap.io"
      UPSTREAM_PORT="587"
      UPSTREAM_USER_HINT="Mailtrap SMTP 用户名"
      UPSTREAM_PASSWORD_HINT="Mailtrap SMTP 密码或 Token"
      ;;
    12)
      UPSTREAM_PROVIDER="QQ 邮箱"
      UPSTREAM_HOST="smtp.qq.com"
      UPSTREAM_PORT="465"
      UPSTREAM_TLS_MODE="ssl"
      UPSTREAM_USER_HINT="QQ 邮箱"
      UPSTREAM_PASSWORD_HINT="QQ 邮箱 SMTP 授权码，不是 QQ 密码"
      ;;
    13)
      UPSTREAM_PROVIDER="163/网易邮箱"
      UPSTREAM_HOST="smtp.163.com"
      UPSTREAM_PORT="465"
      UPSTREAM_TLS_MODE="ssl"
      UPSTREAM_USER_HINT="163/网易邮箱"
      UPSTREAM_PASSWORD_HINT="网易邮箱客户端授权码，不是登录密码"
      ;;
    14)
      UPSTREAM_PROVIDER="自定义 SMTP"
      UPSTREAM_HOST="$(read_required "上游 SMTP 主机")"
      UPSTREAM_PORT="$(read_default "上游 SMTP 端口" "587")"
      validate_port "$UPSTREAM_PORT"
      echo "请选择上游 SMTP 加密方式："
      echo "  1) STARTTLS（常见端口 587）"
      echo "  2) SSL/TLS wrapper/隐式 TLS（常见端口 465）"
      local tls_choice=""
      tls_choice="$(read_default "请选择" "1")"
      case "$tls_choice" in
        1) UPSTREAM_TLS_MODE="starttls" ;;
        2) UPSTREAM_TLS_MODE="ssl" ;;
        *) fail "无效上游 TLS 选择：${tls_choice}" ;;
      esac
      ;;
    *)
      fail "无效选择：${choice}"
      ;;
  esac
}

read_cert_domain() {
  local prompt="$1"
  local domain=""
  while true; do
    domain="$(read_required "$prompt")"
    if is_valid_domain "$domain"; then
      printf '%s' "$domain"
      return 0
    fi
    echo "域名格式不正确，请输入类似 smtp-relay.example.com 的完整域名。"
  done
}

select_tls_mode() {
  echo
  echo "请选择客户端到中继服务的 TLS 证书方式："
  echo "  1) 自动生成自签证书（最简单；客户端严格校验证书时可能需要允许自签）"
  echo "  2) 自动申请 Let's Encrypt 正式证书（中文提示：需要域名解析到本机，并且 80 端口能从公网访问）"
  echo "  3) 使用已有 Let's Encrypt 证书（只填域名，脚本自动选择 /etc/letsencrypt/live/<域名>/ 路径）"
  echo "  4) 使用自定义证书目录（自己填目录；脚本自动读取目录里的 fullchain.pem 和 privkey.pem）"

  TLS_MODE="$(read_default "请选择" "1")"
  CERT_DIR="/etc/postfix/certs"
  CERT_FILE="${CERT_DIR}/relay.crt"
  KEY_FILE="${CERT_DIR}/relay.key"
  CERT_DOMAIN=""
  CUSTOM_CERT_DIR=""
  CERT_SOURCE="自签证书"

  case "$TLS_MODE" in
    1)
      MAILNAME="$(default_hostname)"
      CERT_SOURCE="自签证书"
      ;;
    2)
      echo
      echo "Let's Encrypt 自动申请说明："
      echo "  - 请先把 中继服务域名解析到这台中继服务器。"
      echo "  - 请确保云安全组/防火墙临时放行 TCP 80。"
      echo "  - 脚本会使用 certbot standalone 模式申请证书。"
      echo "  - 脚本不会要求你填写邮箱，会使用 certbot 的无邮箱注册参数。"
      CERT_DOMAIN="$(read_cert_domain "请输入 中继服务域名，例如 smtp-relay.example.com")"
      MAILNAME="$CERT_DOMAIN"
      CERT_SOURCE="Let's Encrypt 自动申请：${CERT_DOMAIN}"
      ;;
    3)
      CERT_DOMAIN="$(read_cert_domain "请输入已有 Let's Encrypt 证书的域名")"
      MAILNAME="$CERT_DOMAIN"
      CERT_FILE="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
      KEY_FILE="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
      CERT_SOURCE="已有 Let's Encrypt 证书：${CERT_DOMAIN}"
      ;;
    4)
      CUSTOM_CERT_DIR="$(read_required "请输入证书目录，目录内必须有 fullchain.pem 和 privkey.pem")"
      CUSTOM_CERT_DIR="${CUSTOM_CERT_DIR%/}"
      CERT_FILE="${CUSTOM_CERT_DIR}/fullchain.pem"
      KEY_FILE="${CUSTOM_CERT_DIR}/privkey.pem"
      MAILNAME="$(default_hostname)"
      CERT_SOURCE="自定义证书目录：${CUSTOM_CERT_DIR}"
      ;;
    *)
      fail "无效 TLS 选择：${TLS_MODE}"
      ;;
  esac
}

install_packages() {
  log "安装 Postfix、SASL、证书和测试工具"
  export DEBIAN_FRONTEND=noninteractive
  echo "postfix postfix/mailname string ${MAILNAME}" | debconf-set-selections
  echo "postfix postfix/main_mailer_type string Internet Site" | debconf-set-selections
  apt-get update
  apt-get install -y postfix sasl2-bin libsasl2-modules ca-certificates openssl mailutils swaks python3
}

validate_certificate_pair() {
  local cert="$1"
  local key="$2"

  [[ -f "$cert" ]] || return 1
  [[ -f "$key" ]] || return 1
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || return 1

  local cert_pub=""
  local key_pub=""
  cert_pub="$(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -r | awk '{print $1}')"
  key_pub="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -r | awk '{print $1}')"
  [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]]
}

set_letsencrypt_paths() {
  CERT_FILE="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
  KEY_FILE="/etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem"
}

retry_or_fail() {
  local message="$1"
  warn "$message"
  local again=""
  again="$(read_default "是否重试？输入 y 重试，输入 n 退出" "y")"
  [[ "$again" =~ ^[Yy]$ ]] || fail "$message"
}

configure_tls() {
  log "配置并验证客户端到 Relay 的 STARTTLS 证书"
  mkdir -p "$CERT_DIR"
  chmod 700 "$CERT_DIR"

  case "$TLS_MODE" in
    1)
      while true; do
        openssl req -x509 -nodes -newkey rsa:4096 \
          -days 3650 \
          -keyout "$KEY_FILE" \
          -out "$CERT_FILE" \
          -subj "/CN=${MAILNAME}" >/dev/null 2>&1
        chmod 600 "$KEY_FILE"
        chmod 644 "$CERT_FILE"
        if validate_certificate_pair "$CERT_FILE" "$KEY_FILE"; then
          break
        fi
        retry_or_fail "自签证书生成后验证失败。"
      done
      ;;
    2)
      apt-get install -y certbot
      while true; do
        set_letsencrypt_paths
        if certbot certonly --standalone \
          --non-interactive \
          --agree-tos \
          --register-unsafely-without-email \
          --preferred-challenges http \
          -d "$CERT_DOMAIN"; then
          if validate_certificate_pair "$CERT_FILE" "$KEY_FILE"; then
            break
          fi
        fi
        retry_or_fail "Let's Encrypt 证书申请或验证失败。请确认域名解析到本机，且 TCP 80 已放行。"
      done
      ;;
    3)
      while true; do
        set_letsencrypt_paths
        if validate_certificate_pair "$CERT_FILE" "$KEY_FILE"; then
          break
        fi
        warn "未找到可用证书，或证书与私钥不匹配：${CERT_FILE} / ${KEY_FILE}"
        CERT_DOMAIN="$(read_cert_domain "请重新输入已有 Let's Encrypt 证书的域名")"
        MAILNAME="$CERT_DOMAIN"
        CERT_SOURCE="已有 Let's Encrypt 证书：${CERT_DOMAIN}"
      done
      ;;
    4)
      while true; do
        CERT_FILE="${CUSTOM_CERT_DIR}/fullchain.pem"
        KEY_FILE="${CUSTOM_CERT_DIR}/privkey.pem"
        if validate_certificate_pair "$CERT_FILE" "$KEY_FILE"; then
          break
        fi
        warn "未找到可用证书，或证书与私钥不匹配：${CERT_FILE} / ${KEY_FILE}"
        CUSTOM_CERT_DIR="$(read_required "请重新输入证书目录，目录内必须有 fullchain.pem 和 privkey.pem")"
        CUSTOM_CERT_DIR="${CUSTOM_CERT_DIR%/}"
        CERT_SOURCE="自定义证书目录：${CUSTOM_CERT_DIR}"
      done
      ;;
  esac

  chmod 644 "$CERT_FILE" || true
  chmod 600 "$KEY_FILE" || true
  log "证书验证通过：${CERT_FILE}"
}

# ============================================================
# Relay 用户管理
# ============================================================

manage_relay_users() {
  log "管理 Relay 用户"

  echo "当前 Relay 用户："
  list_relay_users
  echo

  while true; do
    echo "Relay 用户管理选项："
    echo "  1) 添加新用户"
    echo "  2) 删除用户"
    echo "  3) 完成并继续（已有用户可用）"

    local user_choice
    user_choice="$(read_default "请选择" "3")"

    case "$user_choice" in
      1) add_relay_user ;;
      2) delete_relay_user ;;
      3) break ;;
      *) warn "无效选择，请重新输入" ;;
    esac
  done
}

add_relay_user() {
  echo
  local username
  username="$(read_required "输入用户名（留空使用默认 relay）")"
  [[ -z "$username" ]] && username="relay"

  # 检查用户是否已存在
  if sasldblistusers2 2>/dev/null | grep -q "${username}@"; then
    warn "用户 ${username} 已存在，将更新密码。"
  fi

  local password
  password="$(confirm_secret "输入密码")"

  echo "$password" | saslpasswd2 -c -p -u "$MAILNAME" "$username" 2>/dev/null && \
    echo "  ✓ 用户 ${username} 创建成功" || \
    echo "  ✗ 用户创建失败，请检查 saslpasswd2 权限"

  echo
}

list_relay_users() {
  echo "  已配置的 Relay 用户："
  if sasldblistusers2 2>/dev/null | grep -q '@'; then
    sasldblistusers2 2>/dev/null | grep '@' | while read line; do
      local user
      user=$(echo "$line" | cut -d: -f1)
      echo "    - $user"
    done
  else
    echo "    （暂无用户）"
  fi
}

delete_relay_user() {
  echo
  local username
  username="$(read_required "输入要删除的用户名")"

  if sasldblistusers2 2>/dev/null | grep -q "${username}@"; then
    saslpasswd2 -d "$username" 2>/dev/null && \
      echo "  ✓ 用户 ${username} 已删除" || \
      echo "  ✗ 用户删除失败"
  else
    echo "  用户 ${username} 不存在"
  fi
  echo
}

configure_upstream_auth() {
  log "写入 ${UPSTREAM_PROVIDER} 上游 SMTP 认证"
  cat > /etc/postfix/sasl_passwd <<EOF_PASSWD
[${UPSTREAM_HOST}]:${UPSTREAM_PORT} ${UPSTREAM_USER}:${UPSTREAM_PASS}
EOF_PASSWD
  chmod 600 /etc/postfix/sasl_passwd
  postmap /etc/postfix/sasl_passwd
  chmod 600 /etc/postfix/sasl_passwd.db
}

configure_relay_auth() {
  log "配置 Relay 用户认证"
  mkdir -p /etc/postfix/sasl
  cat > /etc/postfix/sasl/smtpd.conf <<'EOF_SASL'
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF_SASL

  # 用户已通过 manage_relay_users 添加，此处只需设置权限
  if [[ -f /etc/sasldb2 ]]; then
    chgrp postfix /etc/sasldb2 || true
    chmod 640 /etc/sasldb2 || true
  fi

  log "Relay 用户列表："
  list_relay_users
}

configure_postfix_main() {
  log "写入 Postfix 主配置"
  echo "$MAILNAME" > /etc/mailname

  postconf -e "myhostname = ${MAILNAME}"
  postconf -e "myorigin = /etc/mailname"
  postconf -e "inet_interfaces = all"
  postconf -e "inet_protocols = ipv4"
  postconf -e "mydestination = localhost"
  postconf -e "mynetworks = 127.0.0.0/8"

  postconf -e "relayhost = [${UPSTREAM_HOST}]:${UPSTREAM_PORT}"
  postconf -e "smtp_sasl_auth_enable = yes"
  postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
  postconf -e "smtp_sasl_security_options = noanonymous"
  postconf -e "smtp_sasl_tls_security_options = noanonymous"
  postconf -e "smtp_tls_security_level = encrypt"
  postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
  postconf -e "smtp_tls_loglevel = 1"
  if [[ "$UPSTREAM_TLS_MODE" == "ssl" ]]; then
    postconf -e "smtp_tls_wrappermode = yes"
  else
    postconf -e "smtp_tls_wrappermode = no"
  fi

  postconf -e "smtpd_tls_cert_file = ${CERT_FILE}"
  postconf -e "smtpd_tls_key_file = ${KEY_FILE}"
  postconf -e "smtpd_tls_security_level = encrypt"
  postconf -e "smtpd_tls_auth_only = yes"
  postconf -e "smtpd_tls_loglevel = 1"

  postconf -e "smtpd_sasl_auth_enable = yes"
  postconf -e "smtpd_sasl_type = cyrus"
  postconf -e "smtpd_sasl_path = smtpd"
  postconf -e "smtpd_sasl_local_domain = ${MAILNAME}"
  postconf -e "smtpd_sasl_security_options = noanonymous"

  postconf -e "smtpd_recipient_restrictions = reject_unauth_destination"
  postconf -e "smtpd_relay_restrictions = permit_sasl_authenticated, reject_unauth_destination"

  postconf -e "smtpd_client_connection_rate_limit = ${CONNECTION_RATE_LIMIT}"
  postconf -e "default_destination_rate_delay = ${DESTINATION_RATE_DELAY}"
}

configure_postfix_master() {
  log "配置自定义 SMTP Relay 监听端口 ${RELAY_PORT}"
  remove_managed_block /etc/postfix/master.cf

  cat >> /etc/postfix/master.cf <<EOF_MASTER

${MANAGED_BEGIN}
${RELAY_PORT} inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/relay-${RELAY_PORT}
  -o smtpd_tls_security_level=encrypt
  -o smtpd_tls_auth_only=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_mynetworks,reject
  -o mynetworks=127.0.0.0/8,${ALLOW_CIDRS}
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=reject_unauth_destination
${MANAGED_END}
EOF_MASTER
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "检测到 ufw，添加来源 IP 限制规则"
    IFS=',' read -ra cidrs <<< "$ALLOW_CIDRS"
    for cidr in "${cidrs[@]}"; do
      cidr="$(trim "$cidr")"
      [[ -z "$cidr" ]] && continue
      ufw allow from "$cidr" to any port "$RELAY_PORT" proto tcp || true
    done
    warn "如果 ufw 尚未启用，脚本不会自动启用它，避免误锁 SSH。需要时请先放行 SSH 再执行 ufw enable。"
  else
    warn "未检测到 ufw。请在云厂商安全组/iptables/nftables 中只允许 ${ALLOW_CIDRS} 访问 TCP ${RELAY_PORT}。"
  fi
}

restart_postfix() {
  log "重启 Postfix"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable postfix
    systemctl restart postfix
  elif command -v service >/dev/null 2>&1; then
    service postfix restart
  else
    warn "未找到 systemctl/service，已完成配置但未自动重启 Postfix。请手动重启 Postfix。"
  fi
}

print_summary() {
  cat <<EOF_SUMMARY

============================================================
安装完成
============================================================

应用服务器项目中填写：
  SMTP_HOST      = 中继服务器IP或 DNS only/灰云域名
  SMTP_PORT      = ${RELAY_PORT}
  SMTP_USER      = 你配置的 Relay 用户名
  SMTP_PASS      = 你配置的 Relay 用户密码
  加密方式       = STARTTLS
  Nodemailer     = secure: false, requireTLS: true

上游 SMTP：
  服务商：${UPSTREAM_PROVIDER}
  地址：${UPSTREAM_HOST}:${UPSTREAM_PORT}
  加密：${UPSTREAM_TLS_MODE}
  用户：${UPSTREAM_USER}

Relay 用户：
$(sasldblistusers2 2>/dev/null | grep '@' | sed 's/^/  /' || echo "  （请查看上方管理输出）")

客户端到 Relay 的证书：
  来源：${CERT_SOURCE}
  证书：${CERT_FILE}
  私钥：${KEY_FILE}

重要安全提醒：
  1. Cloudflare 普通小黄云不能直接代理 SMTP/TCP，请用灰云 DNS only。
  2. 云厂商安全组也要只允许应用服务器 IP 访问 TCP ${RELAY_PORT}。
  3. 上游 SMTP 密码/API Key 保存在 /etc/postfix/sasl_passwd，仅 root 可读。
  4. 如果使用自签证书，客户端需要允许该证书，或关闭严格证书校验；生产建议使用正式证书。

管理 Relay 用户：
  添加用户: saslpasswd2 -a postfix -u <mailname> <username>
  删除用户: saslpasswd2 -d <username>
  列出用户: sasldblistusers2

查看状态：
  systemctl status postfix --no-pager

查看日志：
  journalctl -u postfix -f
  tail -f /var/log/mail.log

EOF_SUMMARY
}

main() {
  need_root
  need_debian_like

  cat <<'EOF_BANNER'
============================================================
通用 SMTP Relay 交互式安装器
============================================================
此脚本会把当前 中继服务器配置为一个需要认证和 STARTTLS 的 SMTP Relay。
应用服务器连接本中继服务，本中继服务 再登录你选择的上游 SMTP 服务商发信。
EOF_BANNER

  RELAY_PORT="$(read_default "中继服务对应用服务器开放的端口" "2525")"
  validate_port "$RELAY_PORT"

  read -r -p "允许访问本中继服务的应用服务器公网 IP/CIDR，多个用逗号分隔，例如 203.0.113.10/32（回车跳过 = 不限制来源）: " ALLOW_RAW
  if [[ -z "$ALLOW_RAW" ]]; then
    warn "未限制来源，任何 IP 都可以访问 Relay 服务！生产环境建议限制来源 IP。"
    ALLOW_CIDRS="0.0.0.0/0"
  else
    ALLOW_CIDRS="$(normalize_cidrs "$ALLOW_RAW")"
    [[ -n "$ALLOW_CIDRS" ]] || fail "允许来源不能为空。"
  fi

  select_provider

  UPSTREAM_USER="$(read_required "$UPSTREAM_USER_HINT")"
  UPSTREAM_PASS="$(read_secret_required "$UPSTREAM_PASSWORD_HINT")"

  # 验证上游账号
  local verify_retry="y"
  while [[ "$verify_retry" =~ ^[Yy]$ ]]; do
    if verify_upstream_credentials "$UPSTREAM_HOST" "$UPSTREAM_PORT" "$UPSTREAM_USER" "$UPSTREAM_PASS" "$UPSTREAM_TLS_MODE" "$UPSTREAM_PROVIDER"; then
      echo "  ✓ 上游账号验证通过"
      verify_retry="n"
    else
      warn "上游账号验证失败，请检查用户名和密码是否正确。"
      verify_retry="$(read_default "是否重试？输入 y 重试，输入 n 跳过验证继续" "y")"
      if [[ "$verify_retry" =~ ^[Yy]$ ]]; then
        UPSTREAM_USER="$(read_required "$UPSTREAM_USER_HINT")"
        UPSTREAM_PASS="$(read_secret_required "$UPSTREAM_PASSWORD_HINT")"
      fi
    fi
  done
  echo

  # Relay 用户管理
  manage_relay_users

  select_tls_mode

  CONNECTION_RATE_LIMIT="30"
  DESTINATION_RATE_DELAY="1s"

  cat <<EOF_CONFIRM

即将配置：
  Relay 监听端口: ${RELAY_PORT}
  允许来源: ${ALLOW_CIDRS}
  Relay 用户: （见上方管理步骤）
  上游服务商: ${UPSTREAM_PROVIDER}
  上游 SMTP: ${UPSTREAM_HOST}:${UPSTREAM_PORT}
  上游加密: ${UPSTREAM_TLS_MODE}
  上游用户: ${UPSTREAM_USER}
  证书来源: ${CERT_SOURCE}
  mailname: ${MAILNAME}

EOF_CONFIRM

  CONFIRM="$(read_default "确认继续？输入 yes 继续" "no")"
  [[ "$CONFIRM" == "yes" ]] || fail "已取消。"

  TS="$(date +%Y%m%d-%H%M%S)"

  install_packages

  log "备份 Postfix 配置"
  backup_file /etc/postfix/main.cf "$TS"
  backup_file /etc/postfix/master.cf "$TS"

  configure_tls
  configure_upstream_auth
  configure_relay_auth
  configure_postfix_main
  configure_postfix_master
  configure_firewall

  log "检查 Postfix 配置"
  postfix check

  restart_postfix
  print_summary
}

main "$@"
