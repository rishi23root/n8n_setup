#!/bin/sh
set -e

# Replace environment variables in nginx config files if they exist
if [ -n "$SUBDOMAIN" ] && [ -n "$DOMAIN_NAME" ]; then
  FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN_NAME}"
  # Replace ${SUBDOMAIN}.${DOMAIN_NAME} in default.conf
  if [ -f /etc/nginx/conf.d/default.conf ]; then
    sed -i "s|\${SUBDOMAIN}.\${DOMAIN_NAME}|${FULL_DOMAIN}|g" /etc/nginx/conf.d/default.conf
  fi
fi

# Execute the original nginx entrypoint
exec /docker-entrypoint.sh "$@"

