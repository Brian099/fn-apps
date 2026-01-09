#!/bin/sh
set -eu

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Track whether we already emitted HTTP headers.
HTTP_SENT=0

DATA_DIR="${DATA_DIR:-/var/apps/fn-wifi-hotspot/target/server}"
CFG_FILE="${CFG_FILE:-$DATA_DIR/hotspot.env}"
NAT_STATE_FILE="${NAT_STATE_FILE:-$DATA_DIR/nat.env}"
PORTS_STATE_FILE="${PORTS_STATE_FILE:-$DATA_DIR/ports.state}"
HOTSPOT_STATE_FILE="${HOTSPOT_STATE_FILE:-$DATA_DIR/hotspot.state}"

# 默认配置
DEFAULT_CONNECTION_NAME="fn-hotspot"
DEFAULT_IFACE=""
DEFAULT_UPLINK_IFACE=""
DEFAULT_IP_CIDR=""
DEFAULT_ALLOW_PORTS=""
DEFAULT_SSID="fn-hotspot"
DEFAULT_PASSWORD="12345678"
DEFAULT_BAND="bg" # bg=2.4G, a=5G
DEFAULT_CHANNEL="6"
DEFAULT_COUNTRY="" # e.g. CN/US; empty = keep current regdom

mkdir -p "$DATA_DIR" 2>/dev/null || true

trim_ws() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

normalize_country() {
  c="$(trim_ws "${1:-}")"
  c="$(printf '%s' "$c" | tr 'a-z' 'A-Z')"
  printf '%s' "$c"
}

apply_regdom() {
  c="$(normalize_country "${1:-}")"
  [ -n "${c:-}" ] || return 0
  command -v iw >/dev/null 2>&1 || return 1
  iw reg set "$c" >/dev/null 2>&1
}

allow_ports_to_rules() {
  # Input: "53,67-68,153/udp,167-168/udp" (spaces allowed)
  # Output: lines "proto\tstart\tend"; returns non-zero on invalid.
  ALLOW_PORTS_ERR=""
  spec="$(trim_ws "${1:-}")"
  [ -n "$spec" ] || return 0

  oldIFS=$IFS
  IFS=','
  # shellcheck disable=SC2086
  set -- $spec
  IFS=$oldIFS

  for tok in "$@"; do
    t="$(trim_ws "$tok")"
    [ -n "$t" ] || continue

    proto="tcp"
    portpart="$t"
    case "$t" in
      */*)
        proto="$(printf '%s' "${t##*/}" | tr 'A-Z' 'a-z')"
        portpart="${t%/*}"
        ;;
    esac

    proto="$(trim_ws "$proto")"
    portpart="$(trim_ws "$portpart")"

    if ! { [ "$proto" = "tcp" ] || [ "$proto" = "udp" ]; }; then
      ALLOW_PORTS_ERR="allowPorts: protocol must be tcp or udp (token: $t)"
      return 1
    fi
    if [ -z "$portpart" ]; then
      ALLOW_PORTS_ERR="allowPorts: missing port (token: $t)"
      return 1
    fi

    start=""
    end=""
    case "$portpart" in
      *-*)
        start="$(trim_ws "${portpart%-*}")"
        end="$(trim_ws "${portpart#*-}")"
        ;;
      *)
        start="$portpart"
        end="$portpart"
        ;;
    esac

    case "$start" in '' | *[!0-9]*) return 1 ;; esac
    case "$end" in '' | *[!0-9]*) return 1 ;; esac

    case "$start" in '' | *[!0-9]*)
      ALLOW_PORTS_ERR="allowPorts: port must be number (token: $t)"
      return 1
      ;;
    esac
    case "$end" in '' | *[!0-9]*)
      ALLOW_PORTS_ERR="allowPorts: port must be number (token: $t)"
      return 1
      ;;
    esac

    [ "$start" -ge 1 ] 2>/dev/null || {
      ALLOW_PORTS_ERR="allowPorts: port out of range 1-65535 (token: $t)"
      return 1
    }
    [ "$end" -ge 1 ] 2>/dev/null || {
      ALLOW_PORTS_ERR="allowPorts: port out of range 1-65535 (token: $t)"
      return 1
    }
    [ "$start" -le 65535 ] 2>/dev/null || {
      ALLOW_PORTS_ERR="allowPorts: port out of range 1-65535 (token: $t)"
      return 1
    }
    [ "$end" -le 65535 ] 2>/dev/null || {
      ALLOW_PORTS_ERR="allowPorts: port out of range 1-65535 (token: $t)"
      return 1
    }
    [ "$start" -le "$end" ] 2>/dev/null || {
      ALLOW_PORTS_ERR="allowPorts: invalid range start>end (token: $t)"
      return 1
    }

    printf '%s\t%s\t%s\n' "$proto" "$start" "$end"
  done
}

validate_allow_ports() {
  ALLOW_PORTS_ERR=""
  allow_ports_to_rules "${1:-}" >/dev/null 2>&1
}

write_ports_state() {
  iface="$1"
  rules="$2"
  umask 077
  if [ -n "${rules:-}" ]; then
    {
      printf 'iface\t%s\n' "$iface"
      printf '%s' "$rules"
    } >"$PORTS_STATE_FILE"
  else
    rm -f "$PORTS_STATE_FILE" 2>/dev/null || true
  fi
}

load_ports_state() {
  ps_iface=""
  ps_rules=""
  [ -r "$PORTS_STATE_FILE" ] || return 0
  ps_iface="$(head -n1 "$PORTS_STATE_FILE" 2>/dev/null | awk -F'\t' '$1=="iface"{print $2}' || true)"
  ps_rules="$(tail -n +2 "$PORTS_STATE_FILE" 2>/dev/null || true)"
}

iptables_allow_port() {
  iface="$1"
  proto="$2"
  start="$3"
  end="$4"
  [ -n "$iface" ] || return 0
  [ -n "$proto" ] || return 0
  [ -n "$start" ] || return 0
  [ -n "$end" ] || return 0
  command -v iptables >/dev/null 2>&1 || return 0

  dport="$start"
  if [ "$start" != "$end" ]; then
    dport="$start:$end"
  fi

  iptables -C INPUT -i "$iface" -p "$proto" --dport "$dport" -m comment --comment "fn-hotspot-allow" -j ACCEPT >/dev/null 2>&1 \
    || iptables -A INPUT -i "$iface" -p "$proto" --dport "$dport" -m comment --comment "fn-hotspot-allow" -j ACCEPT >/dev/null 2>&1 \
    || true
}

iptables_remove_port() {
  iface="$1"
  proto="$2"
  start="$3"
  end="$4"
  [ -n "$iface" ] || return 0
  command -v iptables >/dev/null 2>&1 || return 0

  dport="$start"
  if [ "$start" != "$end" ]; then
    dport="$start:$end"
  fi

  iptables -D INPUT -i "$iface" -p "$proto" --dport "$dport" -m comment --comment "fn-hotspot-allow" -j ACCEPT >/dev/null 2>&1 || true
}

apply_allow_ports() {
  hotspot_iface="$1"
  spec="$2"
  [ -n "${hotspot_iface:-}" ] || return 0

  # Clean previous rules first (in case iface/spec changed).
  remove_allow_ports

  rules_out=""
  if [ -n "${spec:-}" ]; then
    rules_out="$(allow_ports_to_rules "$spec" 2>/dev/null || true)"
  fi

  if [ -z "${rules_out:-}" ]; then
    write_ports_state "$hotspot_iface" ""
    return 0
  fi

  TAB="$(printf '\t')"
  applied=""
  while IFS="$TAB" read -r proto start end; do
    [ -n "${proto:-}" ] || continue
    iptables_allow_port "$hotspot_iface" "$proto" "$start" "$end"
    applied="$applied$proto$TAB$start$TAB$end\n"
  done <<EOF
$rules_out
EOF

  write_ports_state "$hotspot_iface" "$(printf '%b' "$applied")"
}

remove_allow_ports() {
  load_ports_state
  [ -n "${ps_iface:-}" ] || {
    rm -f "$PORTS_STATE_FILE" 2>/dev/null || true
    return 0
  }
  [ -n "${ps_rules:-}" ] || {
    rm -f "$PORTS_STATE_FILE" 2>/dev/null || true
    return 0
  }

  TAB="$(printf '\t')"
  while IFS="$TAB" read -r proto start end; do
    [ -n "${proto:-}" ] || continue
    iptables_remove_port "$ps_iface" "$proto" "$start" "$end"
  done <<EOF
$ps_rules
EOF

  rm -f "$PORTS_STATE_FILE" 2>/dev/null || true
}

detect_route_dev() {
  # Best-effort: find the interface used to reach a public IP.
  target="${1:-1.1.1.1}"
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get "$target" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}' || true
  fi
}

ensure_ip_forward() {
  command -v sysctl >/dev/null 2>&1 || return 0
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
}

write_nat_state() {
  umask 077
  cat >"$NAT_STATE_FILE" <<EOF
HOTSPOT_IFACE=$(printf '%s' "$1")
NAT_UPLINK_IFACE=$(printf '%s' "$2")
HOTSPOT_PARENT_IFACE=$(printf '%s' "${3:-}")
HOTSPOT_VIRTUAL_IFACE=$(printf '%s' "${4:-}")
EOF
}

clear_nat_state() {
  rm -f "$NAT_STATE_FILE" 2>/dev/null || true
}

write_hotspot_state() {
  # write 1 = enabled, 0 = disabled
  en="$1"
  umask 077
  case "$en" in
    1 | 0) : ;;
    true) en=1 ;;
    false) en=0 ;;
    *) en=0 ;;
  esac
  cat >"$HOTSPOT_STATE_FILE" <<EOF
ENABLED=$en
EOF
}

clear_hotspot_state() {
  rm -f "$HOTSPOT_STATE_FILE" 2>/dev/null || true
}

load_hotspot_state() {
  HOTSPOT_ENABLED=0
  if [ -f "$HOTSPOT_STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$HOTSPOT_STATE_FILE" || true
    case "${ENABLED:-0}" in
      1) HOTSPOT_ENABLED=1 ;;
      *) HOTSPOT_ENABLED=0 ;;
    esac
  fi
}

load_nat_state() {
  HOTSPOT_IFACE=""
  NAT_UPLINK_IFACE=""
  HOTSPOT_PARENT_IFACE=""
  HOTSPOT_VIRTUAL_IFACE=""
  if [ -f "$NAT_STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$NAT_STATE_FILE" || true
  fi
}

iptables_apply_nat() {
  hotspot="$1"
  uplink="$2"
  [ -n "$hotspot" ] || return 0
  [ -n "$uplink" ] || return 0
  command -v iptables >/dev/null 2>&1 || return 0

  # NAT masquerade
  iptables -t nat -C POSTROUTING -o "$uplink" -j MASQUERADE >/dev/null 2>&1 \
    || iptables -t nat -A POSTROUTING -o "$uplink" -j MASQUERADE >/dev/null 2>&1 \
    || true

  # Allow forwarding between hotspot and uplink
  iptables -C FORWARD -i "$hotspot" -o "$uplink" -j ACCEPT >/dev/null 2>&1 \
    || iptables -A FORWARD -i "$hotspot" -o "$uplink" -j ACCEPT >/dev/null 2>&1 \
    || true
  iptables -C FORWARD -i "$uplink" -o "$hotspot" -j ACCEPT >/dev/null 2>&1 \
    || iptables -A FORWARD -i "$uplink" -o "$hotspot" -j ACCEPT >/dev/null 2>&1 \
    || true
}

iptables_remove_nat() {
  hotspot="$1"
  uplink="$2"
  [ -n "$hotspot" ] || return 0
  [ -n "$uplink" ] || return 0
  command -v iptables >/dev/null 2>&1 || return 0

  iptables -t nat -D POSTROUTING -o "$uplink" -j MASQUERADE >/dev/null 2>&1 || true
  iptables -D FORWARD -i "$hotspot" -o "$uplink" -j ACCEPT >/dev/null 2>&1 || true
  iptables -D FORWARD -i "$uplink" -o "$hotspot" -j ACCEPT >/dev/null 2>&1 || true
}

apply_hotspot_nat() {
  hotspot="$1"
  uplink="$2"
  parent_iface="${3:-}"
  virtual_iface="${4:-}"
  [ -n "$hotspot" ] || return 0

  # Prefer caller-provided uplink; else follow actual route.
  if [ -z "${uplink:-}" ]; then
    uplink="$(detect_route_dev 1.1.1.1)"
  fi

  # Always write state so other endpoints can find the actual hotspot iface.
  # NAT is best-effort: uplink may be empty (no internet sharing).
  write_nat_state "$hotspot" "${uplink:-}" "${parent_iface:-}" "${virtual_iface:-}"

  # If uplink is still empty, skip NAT.
  [ -n "${uplink:-}" ] || return 0

  ensure_ip_forward
  iptables_apply_nat "$hotspot" "$uplink"
}

# STA+AP concurrent support & virtual AP iface helpers

iw_supports_sta_ap() {
  # Returns 0 if driver reports a valid interface combination that includes both managed (STA) and AP.
  command -v iw >/dev/null 2>&1 || return 1
  iw list 2>/dev/null | awk '
    BEGIN{in_section=0; ok=0}
    /valid interface combinations/ {in_section=1; next}
    in_section && /^[^[:space:]]/ {in_section=0}
    in_section && /^[[:space:]]*\*/ {
      line=$0;
      if (line ~ /managed/ && line ~ /[[:space:]]AP([[:space:]]|$)/) {ok=1; exit}
    }
    END{exit ok?0:1}
  '
}

mk_ap_iface_name() {
  # Linux IFNAMSIZ-1 is typically 15.
  base="$(trim_ws "${1:-}")"
  suf="ap"
  max=15
  name="${base}${suf}"
  if [ ${#name} -le $max ] 2>/dev/null; then
    printf '%s' "$name"
    return 0
  fi
  blen=$((max - ${#suf}))
  if [ "$blen" -lt 1 ] 2>/dev/null; then
    printf '%s' "ap0"
    return 0
  fi
  printf '%s' "$base" | cut -c1-"$blen"
  printf '%s' "$suf"
}

ensure_virtual_ap_iface() {
  parent="$1"
  ap_iface="$2"
  [ -n "${parent:-}" ] || return 1
  [ -n "${ap_iface:-}" ] || return 1
  command -v iw >/dev/null 2>&1 || return 1

  if iw dev "$ap_iface" info >/dev/null 2>&1; then
    return 0
  fi

  # Create a new virtual AP interface on the same PHY.
  iw dev "$parent" interface add "$ap_iface" type __ap >/dev/null 2>&1 || return 1
  if command -v ip >/dev/null 2>&1; then
    ip link set "$ap_iface" up >/dev/null 2>&1 || true
  fi
  # Best-effort: let NetworkManager manage the new device.
  if command -v nmcli >/dev/null 2>&1; then
    nmcli dev set "$ap_iface" managed yes >/dev/null 2>&1 || true
  fi
  return 0
}

delete_iface() {
  iface="$1"
  [ -n "${iface:-}" ] || return 0
  command -v iw >/dev/null 2>&1 || return 0
  iw dev "$iface" del >/dev/null 2>&1 || true
}

remove_hotspot_nat() {
  load_nat_state
  if [ -n "${HOTSPOT_IFACE:-}" ] && [ -n "${NAT_UPLINK_IFACE:-}" ]; then
    iptables_remove_nat "$HOTSPOT_IFACE" "$NAT_UPLINK_IFACE"
  fi
  clear_nat_state
}

# 输出 JSON（最小转义）
json_escape() {
  # JSON string escape (best-effort, portable): handle \, ", newlines and common control chars.
  # Avoid sed-variant escaping edge cases by using awk.
  printf '%s' "$1" | awk 'BEGIN{ORS=""; first=1}
    {
      if (!first) printf "\\n";
      first=0;
      gsub(/\\\\/,"\\\\\\\\");
      gsub(/\"/,"\\\\\"");
      gsub(/\t/,"\\\\t");
      gsub(/\r/,"");
      gsub(/\f/,"\\\\f");
      printf "%s", $0;
    }'
}

strip_ansi() {
  # Remove common ANSI escape sequences (CSI) from stdin.
  # This keeps JSON output clean when commands print terminal control codes.
  awk 'BEGIN{esc=sprintf("%c",27)}{gsub(esc "\\[[0-9;]*[A-Za-z]", ""); print}'
}

sanitize_text() {
  # Best-effort: strip ANSI + CR. Input is a single string.
  printf '%s' "$1" | strip_ansi | tr -d '\r'
}

# --- i18n (backend messages) ---

UI_LANG=""

qs_get() {
  # Get querystring param by key (URL-decoded). Best-effort.
  # Usage: qs_get lang
  key="$1"
  [ -n "${key:-}" ] || {
    printf '%s' ""
    return 0
  }
  raw="$(printf '%s' "${QUERY_STRING:-}" | tr '&' '\n' | sed -n "s/^${key}=//p" | head -n1)"
  url_decode "${raw:-}"
}

detect_ui_lang() {
  # 1) explicit query param
  v="$(qs_get lang)"
  case "${v:-}" in
    zh | zh-cn | zh_CN | zh-CN)
      UI_LANG="zh"
      return 0
      ;;
    en | en-us | en_US | en-US)
      UI_LANG="en"
      return 0
      ;;
  esac

  # 2) Accept-Language header
  al="${HTTP_ACCEPT_LANGUAGE:-}"
  case "${al:-}" in
    zh* | *",zh"* | *" zh"* | *"zh-"* | *"zh_"*)
      UI_LANG="zh"
      return 0
      ;;
  esac

  UI_LANG="en"
  return 0
}

ui_lang() {
  if [ -z "${UI_LANG:-}" ]; then
    detect_ui_lang
  fi
  printf '%s' "${UI_LANG:-en}"
}

ui_notice_line() {
  # Usage: ui_notice_line "message" -> prints a localized single-line notice.
  # Returns empty if message is empty.
  msg="${1:-}"
  [ -n "${msg:-}" ] || return 0
  msg="$(localize_msg "$msg")"
  if [ "$(ui_lang)" = "zh" ]; then
    printf '%s' "注意：$msg"
  else
    printf '%s' "Notice: $msg"
  fi
}

localize_msg() {
  msg="$1"
  [ -n "${msg:-}" ] || {
    printf '%s' ""
    return 0
  }
  lang="$(ui_lang)"
  [ "${lang:-}" = "zh" ] || {
    printf '%s' "$msg"
    return 0
  }

  # Exact/common messages first.
  case "$msg" in
    "invalid config")
      printf '%s' "配置无效"
      return 0
      ;;
  esac

  # Best-effort mapping for validation-style errors.
  # Keep unknown parts (e.g. regdom details) as-is.
  printf '%s' "$msg" | sed \
    -e "s/^Using virtual AP iface '\([^']*\)' (STA on '\([^']*\)' kept)\.$/使用虚拟 AP 接口 '\1'（保留 '\2' 的 STA 连接）。/" \
    -e "s/^Driver reports STA[+]AP support, but failed to create virtual AP iface; will disconnect STA and use '\([^']*\)'\.$/驱动报告支持 STA+AP，但创建虚拟 AP 接口失败；将断开 STA 并使用 '\1'。/" \
    -e "s/^Adapter does not support STA[+]AP; disconnected '\([^']*\)' on '\([^']*\)'\.$/网卡不支持 STA+AP，已断开 '\2' 上的 '\1'。/" \
    -e "s/^Adapter does not support STA[+]AP; hotspot will use '\([^']*\)' (may interrupt Wi-Fi)\.$/网卡不支持 STA+AP，将使用 '\1' 开热点（可能中断 Wi‑Fi）。/" \
    -e "s/^No Wi-Fi device found\. Check 'nmcli dev status'\.$/未找到 Wi‑Fi 网卡，请检查 'nmcli dev status'。/" \
    -e "s/^Device '\(.*\)' is not a Wi-Fi device\. Wi-Fi devices: /设备 '\1' 不是 Wi‑Fi 网卡。可用 Wi‑Fi 网卡：/" \
    -e 's/^no wifi iface$/未检测到 Wi‑Fi 网卡/' \
    -e 's/^iw not found$/未找到 iw 命令/' \
    -e 's/^invalid mac: /MAC 地址不合法：/' \
    -e 's/^connectionName: required$/connectionName：必填/' \
    -e 's/^ssid: required$/ssid：必填/' \
    -e 's/^password: length must be >= 8$/password：长度必须 >= 8/' \
    -e 's/^uplinkIface: invalid interface name$/uplinkIface：网卡名不合法/' \
    -e 's/^ipCidr: invalid IPv4 CIDR (e.g\. 192\.168\.12\.1\/24)$/ipCidr：IPv4 CIDR 不合法（例如 192.168.12.1\/24）/' \
    -e 's/^allowPorts: invalid format (e\.g\. 53,67-68\/udp,443)$/allowPorts：格式不合法（例如 53,67-68\/udp,443）/' \
    -e 's/^band: must be bg (2\.4G) or a (5G)$/band：必须为 bg (2.4G) 或 a (5G)/' \
    -e 's/^channel: must be a number$/channel：必须是数字/' \
    -e 's/^channel: for band bg (2\.4G), use 1-14$/channel：2.4G (bg) 请使用 1-14/' \
    -e 's/^channel: for band a (5G), use a 5GHz channel (e\.g\. 36\/40\/44\/48\/149\.\.\.)$/channel：5G (a) 请使用 5GHz 信道（例如 36\/40\/44\/48\/149...）/' \
    -e 's/^country: must be empty or a 2-letter code (e\.g\. CN\/US)$/country：必须为空或 2 位国家码（例如 CN\/US）/' \
    -e 's/^save config failed (CFG_FILE not writable)$/保存配置失败（CFG_FILE 不可写）/' \
    -e 's/^nmcli: failed to bring up hotspot connection /nmcli：启动热点连接失败：/' \
    -e 's/^kick failed: /下线失败：/' \
    -e 's/^kick\.cgi failed /kick.cgi 执行失败：/' \
    -e 's/^Connection name conflict: /连接名冲突：/' \
    -e "s/^Device '\(.*\)' does not appear to support AP\/hotspot mode .*$/设备 '\1' 似乎不支持 AP\/热点模式（iw list 未发现 '* AP'）。请更换无线网卡。/" \
    -e 's/^uplinkIface cannot be the same as hotspot iface /uplinkIface 不能与热点网卡相同：/' \
    -e 's/^Tips:$/建议：/' \
    -e 's/hotspot may not be allowed/可能不允许开启热点/g' \
    -e 's/Try band bg (2\.4G) or pick another 5G channel/建议改用 bg (2.4G) 或选择其他 5G 信道/g' \
    -e 's/Try band bg (2\.4G) or set regulatory domain (e\.g\. iw reg set <CC>)/建议改用 bg (2.4G) 或设置监管域（例如 iw reg set <CC>）/g' \
    -e "s/If regdom stays 00 or differs from configured country, your driver\/kernel may be self-managed and ignoring 'iw reg set'\./如果 regdom 一直为 00 或与配置国家码不一致，可能是驱动\/内核在自管监管域并忽略 'iw reg set'。/g" \
    -e 's/exists but is not a hotspot/已存在但不是热点连接/g' \
    -e 's/Please choose another connectionName\/SSID or rename the existing connection\./请更换 connectionName\/SSID 或重命名现有连接。/g' \
    -e 's/cannot rename hotspot connection/无法重命名热点连接/g' \
    -e 's/Choose another uplink interface or leave uplinkIface empty (auto)\./请选择其他上联网卡或将 uplinkIface 留空（自动）。/g' \
    -e 's/unless STA\+AP concurrent mode is available/除非支持 STA+AP 并发模式/g' \
    -e 's/^allowPorts: protocol must be tcp or udp/allowPorts：协议必须为 tcp 或 udp/' \
    -e 's/^allowPorts: missing port/allowPorts：缺少端口/' \
    -e 's/^allowPorts: port must be number/allowPorts：端口必须是数字/' \
    -e 's/^allowPorts: port out of range 1-65535/allowPorts：端口范围必须为 1-65535/' \
    -e 's/^allowPorts: invalid range start>end/allowPorts：端口范围无效（起始 > 结束）/' \
    -e 's/^channel:/信道：/' \
    -e 's/^band:/频段：/' \
    -e 's/^password:/password：/' \
    -e 's/^allowPorts:/allowPorts：/' \
    -e 's/^country:/country：/' \
    -e 's/is disabled/已被禁用/g' \
    -e "s/is marked 'no IR'/标记为 'no IR'/g"
}

http_json() {
  HTTP_SENT=1
  printf 'Content-Type: application/json\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
}

cgi_install_trap() {
  # Best-effort safety net: if a CGI exits non-zero before sending headers,
  # respond with a JSON 500 instead of letting the web server generate HTML.
  # Call this early in each .cgi (after sourcing common.sh).
  trap 'rc=$?; if [ "$rc" -ne 0 ]; then if [ "${HTTP_SENT:-0}" -ne 1 ]; then http_err "500 Internal Server Error" "unexpected error (rc=$rc, step=${STEP:-unknown})"; else exit 0; fi; fi' EXIT
}

http_err() {
  code="$1"
  msg="$2"
  printf 'Status: %s\r\n' "$code"
  http_json
  msg_loc="$(localize_msg "${msg:-}")"
  msg_clean="$(sanitize_text "${msg_loc:-}")"
  printf '{ "ok": false, "error": "%s" }\n' "$(json_escape "$msg_clean")"
  exit 0
}

http_ok() {
  http_ok_begin
  http_ok_end
}

http_ok_output() {
  # Usage: http_ok_output "output" [notice]
  # output: raw multi-line text
  # notice: optional raw notice message (will be localized and prefixed via ui_notice_line)
  out="${1:-}"
  notice="${2:-}"

  out_all="$out"
  if [ -n "${notice:-}" ]; then
    if [ -n "${out_all:-}" ]; then
      out_all="$out_all
$(ui_notice_line "$notice")"
    else
      out_all="$(ui_notice_line "$notice")"
    fi
  fi

  out_clean="$(sanitize_text "${out_all:-}")"
  http_ok_begin
  json_kv_string "output" "$out_clean"
  http_ok_end
}

# --- JSON writer helpers (success responses) ---

JSON_LEVEL=0

json__set_first() {
  v="$1"
  eval "JSON_FIRST_${JSON_LEVEL}='$v'"
}

json__get_first() {
  eval "printf '%s' \"\${JSON_FIRST_${JSON_LEVEL}:-1}\""
}

json__set_type() {
  t="$1"
  eval "JSON_TYPE_${JSON_LEVEL}='$t'"
}

json__get_type() {
  eval "printf '%s' \"\${JSON_TYPE_${JSON_LEVEL}:-obj}\""
}

json__push() {
  t="$1"
  JSON_LEVEL=$((JSON_LEVEL + 1))
  eval "JSON_FIRST_${JSON_LEVEL}=1"
  eval "JSON_TYPE_${JSON_LEVEL}='$t'"
}

json__pop() {
  JSON_LEVEL=$((JSON_LEVEL - 1))
  [ "$JSON_LEVEL" -ge 0 ] 2>/dev/null || JSON_LEVEL=0
}

json__comma() {
  first="$(json__get_first)"
  if [ "$first" = "1" ]; then
    json__set_first 0
  else
    printf ', '
  fi
}

http_ok_begin() {
  http_json
  JSON_LEVEL=0
  json__set_type obj
  # root already contains "ok":true, so next field needs comma
  eval "JSON_FIRST_0=0"
  printf '{ "ok": true'
}

http_ok_end() {
  # Close any unclosed nested containers (best-effort)
  while [ "$JSON_LEVEL" -gt 0 ] 2>/dev/null; do
    json_end
  done
  printf ' }\n'
}

json_kv_string() {
  key="$1"
  val="${2:-}"
  json__comma
  printf '"%s":"%s"' "$key" "$(json_escape "$val")"
}

json_kv_raw() {
  key="$1"
  raw="${2:-}"
  json__comma
  printf '"%s":%s' "$key" "$raw"
}

json_kv_bool() {
  key="$1"
  b="$2"
  case "$b" in
    true | false) : ;;
    *) b=false ;;
  esac
  json_kv_raw "$key" "$b"
}

json_kv_null() {
  key="$1"
  json_kv_raw "$key" null
}

json_begin_object() {
  # Begin an object as an array item (or as a value after json__comma done by caller)
  json__comma
  printf '{'
  json__push obj
}

json_begin_array() {
  json__comma
  printf '['
  json__push arr
}

json_begin_named_object() {
  key="$1"
  json__comma
  printf '"%s":{' "$key"
  json__push obj
}

json_begin_named_array() {
  key="$1"
  json__comma
  printf '"%s":[' "$key"
  json__push arr
}

json_arr_add_string() {
  val="${1:-}"
  json__comma
  printf '"%s"' "$(json_escape "$val")"
}

json_arr_add_raw() {
  raw="${1:-}"
  json__comma
  printf '%s' "$raw"
}

json_end() {
  t="$(json__get_type)"
  case "$t" in
    arr) printf ']' ;;
    *) printf '}' ;;
  esac
  json__pop
}

http_ok_json() {
  # Usage: http_ok_json '"k":1,"obj":{...}'
  # Caller provides JSON members (without outer braces). Best-effort.
  body="${1:-}"
  http_ok_begin
  if [ -n "${body:-}" ]; then
    printf ', %s' "$body"
  fi
  http_ok_end
}

wifi_ifaces() {
  if command -v nmcli >/dev/null 2>&1; then
    # TYPE 在不同环境可能是 wifi / wifi-p2p / 802-11-wireless 等
    nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | awk -F: '
      # Exclude Wi‑Fi P2P virtual devices (e.g. p2p-dev-wlo1, type wifi-p2p)
      ($2 == "wifi-p2p") {next}
      ($2 == "wifi") || ($2 ~ /wireless/) {print $1}
    '
    return 0
  fi

  # Fallback: parse from `iw dev` output
  if command -v iw >/dev/null 2>&1; then
    iw dev 2>/dev/null | sed -n 's/^\s*Interface \(.*\)$/\1/p' \
      | awk '!/^p2p-/ && !/^p2p-dev-/'
    return 0
  fi

  return 0
}

is_iface_name() {
  # Linux interface name (best-effort). Allow '', handled by caller.
  n="$1"
  printf '%s' "$n" | grep -Eq '^[a-zA-Z0-9_.:-]{1,64}$'
}

is_ipv4_cidr() {
  cidr="$1"
  printf '%s' "$cidr" | awk -F'/' '
    NF==2 {
      ip=$1; p=$2;
      if (p !~ /^[0-9]+$/) exit 1;
      if (p < 0 || p > 32) exit 1;
      n=split(ip, a, ".");
      if (n != 4) exit 1;
      for (i=1; i<=4; i++) {
        if (a[i] !~ /^[0-9]+$/) exit 1;
        if (a[i] < 0 || a[i] > 255) exit 1;
      }
      exit 0
    }
    { exit 1 }
  '
}

iw_channel_line() {
  # Best-effort: return the first "* <freq> MHz [<channel>] ..." line from `iw list`.
  # Output empty if not found or iw not available.
  ch="$1"
  [ -n "${ch:-}" ] || return 0
  command -v iw >/dev/null 2>&1 || return 0
  iw list 2>/dev/null | sed -n "s/^[[:space:]]*\* \([0-9][0-9]* MHz \[${ch}\].*\)$/\1/p" | head -n1 || true
}

iw_reg_country() {
  # Best-effort: return country code from `iw reg get` (e.g. CN/US/00).
  command -v iw >/dev/null 2>&1 || return 0
  iw reg get 2>/dev/null | awk '/^country /{gsub(":","",$2); print $2; exit}' || true
}

iw_channels_for_band() {
  band="$1"
  command -v iw >/dev/null 2>&1 || return 0

  case "$band" in
    bg|2.4g|2g)
      band_pat="Band 1:"
      ;;
    a|5g|5G)
      band_pat="Band 2:"
      ;;
    *)
      return 1
      ;;
  esac

  iw list 2>/dev/null | awk -v pat="$band_pat" '
    BEGIN{in_band=0}
    $0 ~ ("^[[:space:]]*" pat) {in_band=1; next}
    in_band && /^[[:space:]]*Band/ {in_band=0}
    in_band && /^[[:space:]]*\*[[:space:]]*[0-9]+ MHz \[[0-9]+\]/ {
      n = index($0, "[")
      m = index($0, "]")
      if (n && m && m > n) {
        ch = substr($0, n+1, m-n-1)
        print ch
      }
    }
  '
}

iface_is_wifi() {
  dev="$1"
  [ -n "$dev" ] || return 1
  command -v nmcli >/dev/null 2>&1 || return 0
  nmcli -t -f DEVICE,TYPE dev status 2>/dev/null | awk -F: -v d="$dev" '
    $1!=d {next}
    $2=="wifi-p2p" {exit 1}
    ($2=="wifi") || ($2 ~ /wireless/) {ok=1}
    END{exit ok?0:1}
  '
}

ensure_iface() {
  # If IFACE is empty, try auto-pick a Wi-Fi device.
  if [ -z "${IFACE:-}" ]; then
    # Prefer a non-P2P device if available (e.g. avoid p2p-dev-wlan0).
    IFACE="$(wifi_ifaces | awk '!/^p2p/ {print; exit}' 2>/dev/null || true)"
    if [ -z "${IFACE:-}" ]; then
      IFACE="$(wifi_ifaces | head -n1 2>/dev/null || true)"
    fi
  fi
}

require_wifi_iface() {
  ensure_iface
  [ -n "${IFACE:-}" ] || return 2
  iface_is_wifi "$IFACE" || return 1
  return 0
}

load_cfg() {
  CONNECTION_NAME="$DEFAULT_CONNECTION_NAME"
  IFACE="$DEFAULT_IFACE"
  UPLINK_IFACE="$DEFAULT_UPLINK_IFACE"
  IP_CIDR="$DEFAULT_IP_CIDR"
  ALLOW_PORTS="$DEFAULT_ALLOW_PORTS"
  SSID="$DEFAULT_SSID"
  PASSWORD="$DEFAULT_PASSWORD"
  BAND="$DEFAULT_BAND"
  CHANNEL="$DEFAULT_CHANNEL"
  COUNTRY="$DEFAULT_COUNTRY"

  if [ -f "$CFG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CFG_FILE" || true
  fi

  : "${CONNECTION_NAME:=$DEFAULT_CONNECTION_NAME}"
  : "${IFACE:=$DEFAULT_IFACE}"
  : "${UPLINK_IFACE:=$DEFAULT_UPLINK_IFACE}"
  : "${IP_CIDR:=$DEFAULT_IP_CIDR}"
  : "${ALLOW_PORTS:=$DEFAULT_ALLOW_PORTS}"
  : "${SSID:=$DEFAULT_SSID}"
  : "${PASSWORD:=$DEFAULT_PASSWORD}"
  : "${BAND:=$DEFAULT_BAND}"
  : "${CHANNEL:=$DEFAULT_CHANNEL}"
  : "${COUNTRY:=$DEFAULT_COUNTRY}"
}

save_cfg() {
  umask 077
  if cat >"$CFG_FILE" <<EOF; then
CONNECTION_NAME=$(printf '%s' "$CONNECTION_NAME")
IFACE=$(printf '%s' "$IFACE")
UPLINK_IFACE=$(printf '%s' "$UPLINK_IFACE")
IP_CIDR=$(printf '%s' "$IP_CIDR")
ALLOW_PORTS=$(printf '%s' "$ALLOW_PORTS")
SSID=$(printf '%s' "$SSID")
PASSWORD=$(printf '%s' "$PASSWORD")
BAND=$(printf '%s' "$BAND")
CHANNEL=$(printf '%s' "$CHANNEL")
COUNTRY=$(printf '%s' "$(normalize_country "${COUNTRY:-}")")
EOF
    return 0
  fi
  return 1
}

validate_runtime_channel() {
  # Should be called at runtime (e.g. start.cgi) after optional regdom is applied.
  # Uses `iw list` to reject channels marked disabled/no IR.
  CFG_ERR=""
  command -v iw >/dev/null 2>&1 || return 0
  ch_line="$(iw_channel_line "$CHANNEL")"
  [ -n "${ch_line:-}" ] || return 0

  case "$ch_line" in
    *"(disabled)"*)
      cc="$(iw_reg_country)"
      [ -n "${cc:-}" ] || cc="unknown"
      conf_cc="$(normalize_country "${COUNTRY:-}")"
      if [ -n "${conf_cc:-}" ]; then
        CFG_ERR="channel: $CHANNEL is disabled (regdom=$cc, configured country=$conf_cc)"
      else
        CFG_ERR="channel: $CHANNEL is disabled (regdom=$cc)"
      fi
      return 1
      ;;
    *"(no IR)"*)
      cc="$(iw_reg_country)"
      [ -n "${cc:-}" ] || cc="unknown"
      conf_cc="$(normalize_country "${COUNTRY:-}")"
      if [ -n "${conf_cc:-}" ]; then
        CFG_ERR="channel: $CHANNEL is marked 'no IR' (regdom=$cc, configured country=$conf_cc), hotspot may not be allowed. Try band bg (2.4G) or pick another 5G channel. If regdom stays 00 or differs from configured country, your driver/kernel may be self-managed and ignoring 'iw reg set'."
      else
        CFG_ERR="channel: $CHANNEL is marked 'no IR' (regdom=$cc), hotspot may not be allowed. Try band bg (2.4G) or set regulatory domain (e.g. iw reg set <CC>)."
      fi
      return 1
      ;;
  esac
  return 0
}

# 读 POST body（支持 application/x-www-form-urlencoded）
read_body() {
  len="${CONTENT_LENGTH:-0}"
  if [ "$len" -gt 0 ] 2>/dev/null; then
    dd bs=1 count="$len" 2>/dev/null
  else
    cat
  fi
}

url_decode() {
  # + => space, %XX 解码（POSIX /bin/sh 兼容；不依赖 printf %b / \\x 支持）
  s="$1"
  out=""
  while [ -n "$s" ]; do
    c="${s%"${s#?}"}"
    s="${s#?}"

    if [ "$c" = "+" ]; then
      out="$out "
      continue
    fi

    if [ "$c" = "%" ]; then
      h1="${s%"${s#?}"}"
      s="${s#?}"
      h2="${s%"${s#?}"}"
      s="${s#?}"
      valid=1
      v1=0
      v2=0

      case "$h1" in
        0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9) v1=$h1 ;;
        a | A) v1=10 ;;
        b | B) v1=11 ;;
        c | C) v1=12 ;;
        d | D) v1=13 ;;
        e | E) v1=14 ;;
        f | F) v1=15 ;;
        *) valid=0 ;;
      esac

      case "$h2" in
        0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9) v2=$h2 ;;
        a | A) v2=10 ;;
        b | B) v2=11 ;;
        c | C) v2=12 ;;
        d | D) v2=13 ;;
        e | E) v2=14 ;;
        f | F) v2=15 ;;
        *) valid=0 ;;
      esac

      if [ "$valid" -eq 1 ]; then
        dec=$((v1 * 16 + v2))
        out="$out$(printf "\\$(printf '%03o' "$dec")")"
      else
        # malformed percent-escape: keep literal
        out="$out%$h1$h2"
      fi
      continue
    fi

    out="$out$c"
  done

  printf '%s' "$out"
}

# 从 form-urlencoded body 中取字段
form_get() {
  key="$1"
  body="$2"
  # shellcheck disable=SC2001
  val="$(printf '%s' "$body" | tr '&' '\n' | sed -n "s/^${key}=//p" | head -n1)"
  url_decode "${val:-}"
}

validate_cfg() {
  CFG_ERR=""
  [ -n "$CONNECTION_NAME" ] || {
    CFG_ERR="connectionName: required"
    return 1
  }
  # IFACE is optional; runtime application happens in start.cgi.
  if [ -n "${UPLINK_IFACE:-}" ] && ! is_iface_name "$UPLINK_IFACE"; then
    CFG_ERR="uplinkIface: invalid interface name"
    return 1
  fi
  if [ -n "${IP_CIDR:-}" ] && ! is_ipv4_cidr "$IP_CIDR"; then
    CFG_ERR="ipCidr: invalid IPv4 CIDR (e.g. 192.168.12.1/24)"
    return 1
  fi
  if [ -n "${ALLOW_PORTS:-}" ] && ! validate_allow_ports "$ALLOW_PORTS"; then
    if [ -n "${ALLOW_PORTS_ERR:-}" ]; then
      CFG_ERR="$ALLOW_PORTS_ERR"
    else
      CFG_ERR="allowPorts: invalid format (e.g. 53,67-68/udp,443)"
    fi
    return 1
  fi
  [ -n "$SSID" ] || {
    CFG_ERR="ssid: required"
    return 1
  }
  [ "${#PASSWORD}" -ge 8 ] || {
    CFG_ERR="password: length must be >= 8"
    return 1
  }
  { [ "$BAND" = "bg" ] || [ "$BAND" = "a" ]; } || {
    CFG_ERR="band: must be bg (2.4G) or a (5G)"
    return 1
  }
  case "$CHANNEL" in
    *[!0-9]* | "")
      CFG_ERR="channel: must be a number"
      return 1
      ;;
  esac

  # Basic band/channel sanity check to catch obvious misconfigurations early.
  # Note: exact allowed channels depend on regulatory domain; we only guard common invalid cases.
  if [ "$BAND" = "bg" ]; then
    if [ "$CHANNEL" -lt 1 ] 2>/dev/null || [ "$CHANNEL" -gt 14 ] 2>/dev/null; then
      CFG_ERR="channel: for band bg (2.4G), use 1-14"
      return 1
    fi
  fi
  if [ "$BAND" = "a" ]; then
    # 5GHz channels are generally >= 34; channel 1-14 are 2.4GHz and will fail with nmcli.
    if [ "$CHANNEL" -lt 34 ] 2>/dev/null; then
      CFG_ERR="channel: for band a (5G), use a 5GHz channel (e.g. 36/40/44/48/149...)"
      return 1
    fi
  fi

  # COUNTRY is optional; runtime application happens in start.cgi.
  c="$(normalize_country "${COUNTRY:-}")"
  if [ -n "${c:-}" ]; then
    case "$c" in
      00) : ;;
      [A-Z][A-Z]) : ;;
      *)
        CFG_ERR="country: must be empty or a 2-letter code (e.g. CN/US)"
        return 1
        ;;
    esac
  fi
  return 0
}
