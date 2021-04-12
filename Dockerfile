FROM php:7.4-apache

RUN apt-get update; \
    apt-get install -y git vim wget apt-utils zip unzip;

RUN apt-get install -y --no-install-recommends \
    libbz2-dev libicu-dev libjpeg-dev libpng-dev libldap2-dev libldb-dev libnotify-bin libpq-dev libxml2-dev libzip-dev zlib1g-dev libfreetype6-dev libjpeg62-turbo-dev;

RUN set -ex; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; 
	
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
RUN apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need
RUN docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-install -j$(nproc) \
        bcmath \
        bz2 \
        exif \
	gd \
        gettext \
        intl \
        ldap \
	opcache \
	pdo_mysql \
	pdo_pgsql \
        xmlrpc \
	zip \
	; 
	


# Use the default development configuration
# see https://hub.docker.com/_/php
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# set recommended opcache PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# download trusted certs
RUN mkdir -p /etc/ssl/certs && update-ca-certificates

# install composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer

# install Xdebug
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug

# see https://xdebug.org/docs/install
RUN { \
    echo 'xdebug.remote_connect_back=0'; \
    echo 'xdebug.remote_autostart=1'; \
    echo 'xdebug.remote_enable=1'; \
    echo 'xdebug.remote_host="host.docker.internal"'; \
    echo 'xdebug.remote_port=9001'; \
    echo 'xdebug.idekey=PHPSTORM'; \
    echo 'memory_limit = 1024M'; \
    echo 'xdebug.remote_log="/tmp/xdebug.log"';\
    } >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# install phpunit, phpcs and phpcbf.
RUN wget -O /usr/local/bin/phpunit https://phar.phpunit.de/phpunit-9.phar \
    && wget -O /usr/local/bin/phpcs https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar \
    && wget -O /usr/local/bin/phpcbf https://squizlabs.github.io/PHP_CodeSniffer/phpcbf.phar \
    && chmod +x /usr/local/bin/php*

# install nodejs, npm, yarn and dependencies
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs autoconf automake g++ gcc libtool make nasm python \
    && npm i -g yarn bower

WORKDIR /var/www/html
CMD bash -c "composer install && npm install && php ./artisan serve --port=80 --host=0.0.0.0"
EXPOSE 80
HEALTHCHECK --interval=1m CMD curl -f http://localhost/ || exit 1
ENV TERM xterm
