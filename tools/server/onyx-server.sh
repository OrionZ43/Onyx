#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Onyx server — одна команда на чистом VPS (Ubuntu / Debian, amd64 или arm64).
#
# Ставит sing-box с двумя транспортами на одном сервере:
#   • VLESS + REALITY + Vision  — TCP, основной (маскируется под чужой HTTPS);
#   • Hysteria2 + salamander    — UDP/QUIC, второй (быстрый, для стримов),
#                                 с port hopping (диапазон UDP-портов).
# Onyx объединяет их в группу с автопереключением, если подключить подписку.
#
# Запуск (на сервере, от root):
#   curl -fsSL https://raw.githubusercontent.com/OrionZ43/Onyx/main/tools/server/onyx-server.sh | sudo bash
# или с параметрами:
#   sudo bash onyx-server.sh --sni www.microsoft.com --port 443 --hop 20000-50000
#
# Параметры:
#   --port N          порт REALITY (TCP) и Hysteria2 (UDP), по умолчанию 443
#   --hop A-B         диапазон UDP для port hopping, по умолчанию 20000-50000;
#                     --hop none — без hopping
#   --sni HOST        сайт для маскировки REALITY и SNI Hysteria2,
#                     по умолчанию www.microsoft.com
#   --name NAME       префикс имён серверов в Onyx, по умолчанию Onyx
#   --regen           сгенерировать новые ключи (старые ссылки перестанут работать)
#   --uninstall       удалить сервис, конфиг и правила
#   --no-system       только сгенерировать конфиг и ссылки в ./onyx-out
#                     (без systemd, iptables и загрузки; нужен SINGBOX_BIN)
#
# Повторный запуск безопасен: ключи сохраняются в /etc/onyx/state.env.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SB_VERSION="1.14.4"
SB_SHA256_amd64="699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968"
SB_SHA256_arm64="436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26"

PORT=443
HOP="20000-50000"
SNI="www.microsoft.com"
NAME="Onyx"
REGEN=0
UNINSTALL=0
NO_SYSTEM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --hop) HOP="$2"; shift 2 ;;
    --sni) SNI="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --regen) REGEN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-system) NO_SYSTEM=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; exit 1 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$NO_SYSTEM" = 1 ]; then
  ETC="${ONYX_OUT:-./onyx-out}"
  SB="${SINGBOX_BIN:?для --no-system укажите SINGBOX_BIN=/путь/к/sing-box}"
else
  ETC="/etc/onyx"
  SB="/usr/local/bin/sing-box"
  [ "$(id -u)" = 0 ] || die "Запустите от root: sudo bash $0"
fi
SERVICE="onyx-singbox"

HOP_FROM=""; HOP_TO=""
if [ "$HOP" != "none" ]; then
  HOP_FROM="${HOP%-*}"; HOP_TO="${HOP#*-}"
  case "$HOP_FROM$HOP_TO" in *[!0-9]*|"") die "--hop: формат A-B, например 20000-50000" ;; esac
fi

# ── Удаление ────────────────────────────────────────────────────────────────
firewall_rules() { # $1 = -I | -D
  local op="$1"
  iptables "$op" INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  iptables "$op" INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || true
  if [ -n "$HOP_FROM" ]; then
    iptables "$op" INPUT -p udp --dport "$HOP_FROM:$HOP_TO" -j ACCEPT 2>/dev/null || true
    iptables -t nat "$op" PREROUTING -p udp --dport "$HOP_FROM:$HOP_TO" -j REDIRECT --to-ports "$PORT" 2>/dev/null || true
  fi
}

persist_firewall() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent >/dev/null 2>&1 \
      && netfilter-persistent save >/dev/null 2>&1 || warn "Не удалось сохранить правила iptables — после перезагрузки запустите скрипт ещё раз"
  fi
}

if [ "$UNINSTALL" = 1 ]; then
  [ "$NO_SYSTEM" = 0 ] || die "--uninstall несовместим с --no-system"
  [ -f "$ETC/state.env" ] && . "$ETC/state.env"
  systemctl disable --now "$SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$SERVICE.service"
  systemctl daemon-reload || true
  firewall_rules -D; persist_firewall
  rm -rf "$ETC"
  say "Onyx server удалён (бинарник $SB оставлен)."
  exit 0
fi

# ── sing-box ────────────────────────────────────────────────────────────────
install_singbox() {
  if [ -x "$SB" ] && "$SB" version 2>/dev/null | grep -q "version $SB_VERSION"; then
    say "sing-box $SB_VERSION уже установлен"; return
  fi
  local arch sha
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64; sha="$SB_SHA256_amd64" ;;
    aarch64|arm64) arch=arm64; sha="$SB_SHA256_arm64" ;;
    *) die "Архитектура $(uname -m) не поддерживается (нужна amd64 или arm64)" ;;
  esac
  command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
  local tmp; tmp="$(mktemp -d)"
  local file="sing-box-$SB_VERSION-linux-$arch.tar.gz"
  say "Скачиваем sing-box $SB_VERSION ($arch)..."
  curl -fsSL --retry 3 -o "$tmp/$file" \
    "https://github.com/SagerNet/sing-box/releases/download/v$SB_VERSION/$file" \
    || die "Не удалось скачать sing-box с GitHub"
  echo "$sha  $tmp/$file" | sha256sum -c --status || die "SHA-256 архива sing-box не совпал — загрузка подменена или повреждена"
  tar -xzf "$tmp/$file" -C "$tmp"
  install -m 0755 "$tmp/sing-box-$SB_VERSION-linux-$arch/sing-box" "$SB"
  rm -rf "$tmp"
  say "sing-box установлен: $("$SB" version | head -1)"
}

[ "$NO_SYSTEM" = 1 ] || install_singbox

# ── Ключи (сохраняются между запусками) ─────────────────────────────────────
mkdir -p "$ETC"; chmod 700 "$ETC"
if [ "$REGEN" = 1 ] || [ ! -f "$ETC/state.env" ]; then
  say "Генерируем ключи..."
  UUID="$("$SB" generate uuid)"
  KP="$("$SB" generate reality-keypair)"
  REALITY_PRIV="$(printf '%s\n' "$KP" | awk '/PrivateKey/ {print $2}')"
  REALITY_PUB="$(printf '%s\n' "$KP" | awk '/PublicKey/ {print $2}')"
  SHORT_ID="$("$SB" generate rand 8 --hex)"
  HY2_PASS="$("$SB" generate rand 16 --hex)"
  OBFS_PASS="$("$SB" generate rand 16 --hex)"
  "$SB" generate tls-keypair "$SNI" -m 120 > "$ETC/tls.pem"
  awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' "$ETC/tls.pem" > "$ETC/hy2.key"
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$ETC/tls.pem" > "$ETC/hy2.crt"
  rm -f "$ETC/tls.pem"
  cat > "$ETC/state.env" <<EOF
UUID='$UUID'
REALITY_PRIV='$REALITY_PRIV'
REALITY_PUB='$REALITY_PUB'
SHORT_ID='$SHORT_ID'
HY2_PASS='$HY2_PASS'
OBFS_PASS='$OBFS_PASS'
EOF
  chmod 600 "$ETC/state.env" "$ETC/hy2.key"
else
  say "Используем сохранённые ключи ($ETC/state.env)"
fi
# shellcheck disable=SC1091
. "$ETC/state.env"

# ── Конфиг ─────────────────────────────────────────────────────────────────
cat > "$ETC/config.json" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "uuid": "$UUID", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$SNI", "server_port": 443 },
          "private_key": "$REALITY_PRIV",
          "short_id": [ "$SHORT_ID" ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "password": "$HY2_PASS" } ],
      "obfs": { "type": "salamander", "password": "$OBFS_PASS" },
      "ignore_client_bandwidth": false,
      "masquerade": "https://$SNI",
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "alpn": [ "h3" ],
        "certificate_path": "$ETC/hy2.crt",
        "key_path": "$ETC/hy2.key"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ],
  "route": { "final": "direct" }
}
EOF
chmod 600 "$ETC/config.json"
"$SB" check -c "$ETC/config.json" || die "sing-box отверг конфиг"

# ── Система: сеть, сервис ───────────────────────────────────────────────────
if [ "$NO_SYSTEM" = 0 ]; then
  say "Включаем BBR и буферы UDP..."
  cat > /etc/sysctl.d/90-onyx.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
  sysctl --system >/dev/null 2>&1 || true

  say "Открываем порты: TCP $PORT, UDP $PORT${HOP_FROM:+, UDP $HOP_FROM-$HOP_TO (hopping)}"
  command -v iptables >/dev/null || { apt-get update -qq && apt-get install -y -qq iptables; }
  firewall_rules -D   # без дублей при повторном запуске
  firewall_rules -I
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$PORT"/tcp >/dev/null; ufw allow "$PORT"/udp >/dev/null
    [ -n "$HOP_FROM" ] && ufw allow "$HOP_FROM:$HOP_TO"/udp >/dev/null
  fi
  persist_firewall

  cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Onyx server (sing-box: VLESS REALITY + Hysteria2)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$SB run -c $ETC/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1
  systemctl restart "$SERVICE"
  sleep 2
  systemctl is-active --quiet "$SERVICE" || { journalctl -u "$SERVICE" -n 30 --no-pager; die "Сервис не запустился"; }
fi

# ── Ссылки для Onyx ─────────────────────────────────────────────────────────
IP="${ONYX_PUBLIC_IP:-}"
if [ -z "$IP" ]; then
  for u in https://api.ipify.org https://ifconfig.me https://ipv4.icanhazip.com; do
    IP="$(curl -4 -fsS --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]')" && [ -n "$IP" ] && break
  done
fi
[ -n "$IP" ] || die "Не удалось определить внешний IP. Задайте ONYX_PUBLIC_IP=... и запустите снова."

urlenc() { local s="$1" o="" c i; for ((i=0; i<${#s}; i++)); do c="${s:i:1}"; case "$c" in [a-zA-Z0-9.~_-]) o+="$c" ;; *) o+="$(printf '%%%02X' "'$c")" ;; esac; done; printf '%s' "$o"; }

VLESS_LINK="vless://$UUID@$IP:$PORT?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=$SNI&fp=chrome&pbk=$REALITY_PUB&sid=$SHORT_ID#$(urlenc "$NAME REALITY")"
HY2_LINK="hysteria2://$HY2_PASS@$IP:$PORT/?sni=$SNI&insecure=1&alpn=h3&obfs=salamander&obfs-password=$OBFS_PASS${HOP_FROM:+&mport=$HOP_FROM-$HOP_TO}#$(urlenc "$NAME Hysteria2")"

printf '%s\n%s\n' "$VLESS_LINK" "$HY2_LINK" > "$ETC/links.txt"
SUB_B64="$(base64 -w0 < "$ETC/links.txt")"
printf '%s\n' "$SUB_B64" > "$ETC/subscription.txt"
chmod 600 "$ETC/links.txt" "$ETC/subscription.txt"

echo
say "Готово! Сервер работает: $IP"
echo
echo "──── Подписка для Onyx (скопируйте ВСЮ строку и вставьте в Onyx → «Добавить подписку») ────"
echo
echo "$SUB_B64"
echo
echo "──── Или две отдельные ссылки ────"
echo "$VLESS_LINK"
echo "$HY2_LINK"
echo
if command -v qrencode >/dev/null; then
  echo "──── QR-код подписки ────"; qrencode -t ANSIUTF8 "$SUB_B64"
fi
echo "Ссылки сохранены в $ETC/links.txt и $ETC/subscription.txt (показать ещё раз: sudo cat $ETC/subscription.txt)"
echo
warn "В панели облака (AWS Lightsail → Networking / EC2 → Security group) должны быть открыты:"
warn "  TCP $PORT, UDP $PORT${HOP_FROM:+, UDP $HOP_FROM-$HOP_TO}"
warn "Никому не показывайте эти ссылки: по ним можно пользоваться вашим сервером."
