#!/bin/sh
# Usage: probe.sh URL CONNECT_HOST
# Prints {"code": "...", "location": "..."} for the external data source.
# Retries while the edge is still picking up the new certificate or alias.
set -eu

url=$1
connect_host=$2
port=443
case $url in http://*) port=80 ;; esac

i=0
while :; do
  out=$(curl -s -o /dev/null --max-time 10 \
    --connect-to "::${connect_host}:${port}" \
    -w '%{http_code} %header{location}' "$url" || true)
  code=${out%% *}
  case $code in 3??) break ;; esac
  i=$((i + 1))
  if [ "$i" -ge 20 ]; then break; fi
  sleep 15
done

location=${out#* }
[ "$location" = "$out" ] && location=""
# Escape for JSON: backslashes and double quotes.
location=$(printf '%s' "$location" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r')
printf '{"code":"%s","location":"%s"}\n' "$code" "$location"
