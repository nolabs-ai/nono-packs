#!/usr/bin/env bash
set -eu

echo "Hermes:"
if command -v hermes >/dev/null 2>&1; then
  hermes --version || true
else
  echo "  hermes: not found on PATH"
fi

echo
echo "nono:"
if command -v nono >/dev/null 2>&1; then
  nono --version || true
else
  echo "  nono: not found on PATH"
fi

echo
echo "nono sandbox:"
if [ -n "${NONO_CAP_FILE:-}" ] && [ -f "$NONO_CAP_FILE" ]; then
  echo "  capability file: $NONO_CAP_FILE"
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      "  network: " + (if .net_blocked then "blocked" else "allowed" end),
      "  filesystem:",
      (.fs[]? | "    " + ((.resolved // .path) | tostring) + " (" + (.access | tostring) + ")")
    ' "$NONO_CAP_FILE"
  else
    echo "  jq not found; raw capability file:"
    sed -n '1,80p' "$NONO_CAP_FILE"
  fi
else
  echo "  not running inside a nono session, or NONO_CAP_FILE is unavailable"
fi

echo
echo "nono proxy and TLS trust:"
for name in HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy OPENAI_BASE_URL ANTHROPIC_BASE_URL GEMINI_BASE_URL SSL_CERT_FILE REQUESTS_CA_BUNDLE NODE_EXTRA_CA_CERTS CURL_CA_BUNDLE GIT_SSL_CAINFO NONO_PROXY_TOKEN; do
  value=$(printenv "$name" 2>/dev/null || true)
  if [ -n "$value" ]; then
    case "$name" in
      NONO_PROXY_TOKEN)
        echo "  $name: set"
        ;;
      HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)
        redacted=$(printf "%s" "$value" | sed -E 's#//[^/@]+@#//<redacted>@#')
        echo "  $name: $redacted"
        ;;
      *)
        echo "  $name: $value"
        ;;
    esac
  fi
done

echo
echo "Hermes security files:"
for path in "$HOME/.hermes/.env" "$HOME/.hermes/config.yaml"; do
  if [ -e "$path" ]; then
    perms=$(stat -f "%Lp" "$path" 2>/dev/null || stat -c "%a" "$path" 2>/dev/null || echo "unknown")
    echo "  $path permissions: $perms"
  else
    echo "  $path: missing"
  fi
done
