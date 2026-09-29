# WordPress (PHP-FPM) + WP-CLI on the PHP versions the official WordPress
# images no longer publish (7.4 and 8.0). Used only by overrides/old-php.yaml,
# to run the store on an older PHP: those PHP versions no longer receive
# security fixes, don't use it in production.
#
# Follows the official image's recipe (docker-library/wordpress, MIT license):
# same extensions, PHP settings, entrypoint and wp-config template, on
# php:<ver>-fpm-alpine, with WP-CLI added (the official one is a separate
# image that has no PHP 7.4/8.0 build for its current versions).

ARG PHP_VERSION=7.4
FROM php:${PHP_VERSION}-fpm-alpine

# persistent dependencies (less and mariadb-client: what the WP-CLI image has)
RUN set -eux; \
    apk add --no-cache bash ghostscript imagemagick less mariadb-client

# PHP extensions WordPress needs
# (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS freetype-dev icu-dev imagemagick-dev \
        libjpeg-turbo-dev libpng-dev libwebp-dev libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j "$(nproc)" bcmath exif gd intl mysqli zip; \
    pecl install imagick-3.7.0; \
    docker-php-ext-enable imagick; \
    rm -r /tmp/pear; \
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive "$extDir" \
            | tr ',' '\n' | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .wordpress-phpexts-rundeps $runDeps; \
    apk del --no-network .build-deps; \
    ! { ldd "$extDir"/*.so | grep 'not found'; }; \
    err="$(php --version 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]

# recommended opcache settings and error logging (as the official image)
RUN set -eux; \
    { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
    } > "$PHP_INI_DIR/conf.d/opcache-recommended.ini"; \
    { \
        echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
        echo 'display_errors = Off'; \
        echo 'display_startup_errors = Off'; \
        echo 'log_errors = On'; \
        echo 'error_log = /dev/stderr'; \
        echo 'log_errors_max_len = 1024'; \
        echo 'ignore_repeated_errors = On'; \
        echo 'ignore_repeated_source = Off'; \
        echo 'html_errors = Off'; \
    } > "$PHP_INI_DIR/conf.d/error-logging.ini"

# WordPress release, verified with its SHA-1 (WP_SHA1 empty skips the check)
ARG WP_VERSION=6.5.5
ARG WP_SHA1=
RUN set -eux; \
    curl -o wordpress.tar.gz -fL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"; \
    if [ -n "${WP_SHA1}" ]; then echo "${WP_SHA1} *wordpress.tar.gz" | sha1sum -c -; fi; \
    tar -xzf wordpress.tar.gz -C /usr/src/; \
    rm wordpress.tar.gz; \
    chown -R www-data:www-data /usr/src/wordpress; \
    mkdir wp-content; \
    for dir in /usr/src/wordpress/wp-content/*/ cache; do \
        dir="$(basename "${dir%/}")"; \
        mkdir "wp-content/$dir"; \
    done; \
    chown -R www-data:www-data wp-content; \
    chmod -R 1777 wp-content

# WP-CLI (phar), verified with its SHA-512 (WPCLI_SHA512 empty skips the check)
ARG WPCLI_VERSION=2.12.0
ARG WPCLI_SHA512=
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar"; \
    if [ -n "${WPCLI_SHA512}" ]; then echo "${WPCLI_SHA512} */usr/local/bin/wp" | sha512sum -c -; fi; \
    chmod +x /usr/local/bin/wp; \
    wp --allow-root --info > /dev/null

VOLUME /var/www/html

COPY --chown=www-data:www-data wp-config-docker.php /usr/src/wordpress/
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/
RUN ln -svfT docker-entrypoint.sh /usr/local/bin/docker-ensure-installed.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm"]
