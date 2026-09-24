#!/bin/sh
# Installs WordPress + WooCommerce and applies the initial store settings.
#
# Runs on every `docker compose up` and is safe to repeat:
# - WordPress and WooCommerce are installed only if missing.
# - Initial settings (language, country, currency, permalinks...) are applied
#   only once, so changes made later in the admin are kept.
# - WC_VERSION, when set, pins WooCommerce to that exact version on every run;
#   when empty, the latest version is installed once and then updated from the
#   admin as usual.
# - The Redis object cache is enabled or disabled to match REDIS_HOST.
set -eu

cd /var/www/html

INIT_OPTION="docker_stack_initialized"

# Redis turned off: remove the Redis Object Cache drop-in before loading
# WordPress, so nothing tries to reach a Redis server that isn't there.
if [ -z "${REDIS_HOST}" ] && grep -qs 'Redis Object Cache' wp-content/object-cache.php; then
    echo "==> REDIS_HOST is empty: removing the Redis object cache drop-in"
    rm -f wp-content/object-cache.php
    redis_disabled=1
fi

if ! wp core is-installed 2>/dev/null; then
    echo "==> Installing WordPress at ${WP_URL}"
    wp core install \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email
fi

current_wc="$(wp plugin get woocommerce --field=version 2>/dev/null || true)"
if [ -z "${current_wc}" ]; then
    echo "==> Installing WooCommerce ${WC_VERSION:-(latest)}"
    wp plugin install woocommerce ${WC_VERSION:+--version="${WC_VERSION}"}
elif [ -n "${WC_VERSION}" ] && [ "${current_wc}" != "${WC_VERSION}" ]; then
    echo "==> Pinning WooCommerce to ${WC_VERSION} (was ${current_wc})"
    wp plugin install woocommerce --version="${WC_VERSION}" --force
fi

if ! wp option get "${INIT_OPTION}" >/dev/null 2>&1; then
    echo "==> Initial settings"
    wp plugin activate woocommerce
    # Sample plugins bundled with WordPress.
    wp plugin delete akismet hello 2>/dev/null || true
    if [ "${WP_LOCALE}" != "en_US" ]; then
        wp language core install "${WP_LOCALE}" --activate
        wp language plugin install woocommerce "${WP_LOCALE}" || true
    fi
    wp option update woocommerce_default_country "${WC_COUNTRY}"
    wp option update woocommerce_currency "${WC_CURRENCY}"
    # Skip the WooCommerce onboarding wizard.
    wp option update woocommerce_onboarding_profile '{"skipped":true}' --format=json
    # Pretty permalinks (Caddy routes them to index.php, see config/caddy).
    wp rewrite structure '/%postname%/'
    wp rewrite flush
    wp option add "${INIT_OPTION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

if [ -n "${REDIS_HOST}" ]; then
    if ! wp plugin is-active redis-cache 2>/dev/null; then
        echo "==> Enabling Redis object cache (${REDIS_HOST})"
        wp plugin install redis-cache --activate
    fi
    wp redis status | grep -q '^Drop-in: Valid' || wp redis enable --force
elif [ -n "${redis_disabled:-}" ]; then
    wp plugin deactivate redis-cache
fi

echo "==> Done: WordPress $(wp core version), WooCommerce $(wp plugin get woocommerce --field=version)"
echo "    Store: ${WP_URL}"
echo "    Admin: ${WP_URL}/wp-admin (user: ${WP_ADMIN_USER})"
