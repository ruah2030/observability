#!/usr/bin/env bash
# Prepares everything the stack needs before `docker compose up -d`:
#   secrets/htpasswd        bcrypt basic auth for admin UIs
#   secrets/smtp_password   read by Alertmanager
#   alertmanager/alertmanager.yml rendered from its template
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
  echo "→ .env created from .env.example. Edit it, then run this script again."
  exit 1
fi

# Read .env without sourcing it: values may contain shell characters.
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  value=${line#*=}
  case "$value" in
    \"*\") value=${value:1:${#value}-2} ;;
    \'*\') value=${value:1:${#value}-2} ;;
  esac
  export "$key=$value"
done < .env

fail() { echo "✗ $*" >&2; exit 1; }

for var in DOMAIN ACME_EMAIL ADMIN_USER ADMIN_PASSWORD GRAFANA_ADMIN_PASSWORD \
           ALERT_EMAIL_TO SMTP_HOST SMTP_FROM SMTP_USER SMTP_PASSWORD; do
  [ -n "${!var:-}" ] || fail "$var is empty in .env"
done
[ "$DOMAIN" != "example.com" ] || fail "set DOMAIN in .env"
for var in ADMIN_PASSWORD GRAFANA_ADMIN_PASSWORD SMTP_PASSWORD; do
  [ "${!var}" != "change-me-now" ] || fail "change $var in .env"
done

mkdir -p secrets
chmod 700 secrets

# ── Basic auth (bcrypt) ──────────────────────────────────────────────
if command -v htpasswd >/dev/null 2>&1; then
  htpasswd -nbB "$ADMIN_USER" "$ADMIN_PASSWORD" > secrets/htpasswd
elif command -v docker >/dev/null 2>&1; then
  docker run --rm httpd:2.4-alpine htpasswd -nbB "$ADMIN_USER" "$ADMIN_PASSWORD" > secrets/htpasswd
else
  fail "htpasswd or docker is required"
fi

# ── SMTP password ────────────────────────────────────────────────────
printf '%s' "$SMTP_PASSWORD" > secrets/smtp_password

# Files are bind-mounted directly, so the 700 directory still protects
# them from other host users while containers (non-root) can read them.
chmod 644 secrets/htpasswd secrets/smtp_password

# ── Alertmanager configuration ───────────────────────────────────────
esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }
sed -e "s|__SMTP_HOST__|$(esc "$SMTP_HOST")|" \
    -e "s|__SMTP_FROM__|$(esc "$SMTP_FROM")|" \
    -e "s|__SMTP_USER__|$(esc "$SMTP_USER")|" \
    -e "s|__ALERT_EMAIL_TO__|$(esc "$ALERT_EMAIL_TO")|" \
    alertmanager/alertmanager.tmpl.yml > alertmanager/alertmanager.yml

if command -v docker >/dev/null 2>&1; then
  docker compose config --quiet && echo "✓ compose.yml is valid"
fi

cat <<MSG
✓ Secrets and Alertmanager configuration ready.

DNS records (A/AAAA) that must point to this server:
  traefik.$DOMAIN  grafana.$DOMAIN  prometheus.$DOMAIN  alertmanager.$DOMAIN

Start the stack:
  docker compose up -d
MSG
