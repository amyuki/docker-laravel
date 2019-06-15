FROM php:7.3-apache

RUN apt-get update; \
    apt-get install -y \
        git \
        vim \
        wget \
        apt-utils \
        ;
# install the PHP extensions we need
RUN set -ex; \
	\
	if command -v a2enmod; then \
		a2enmod rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get install -y --no-install-recommends \
        libbz2-dev \
        libicu-dev \
		libjpeg-dev \
        libldap2-dev \
        libldb-dev \
        libnotify-bin \
		libpng-dev \
		libpq-dev \
        libxml2-dev \
		libzip-dev \
        zlib1g-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install -j "$(nproc)" \
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
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
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
RUN wget -O /usr/local/bin/phpunit https://phar.phpunit.de/phpunit-8.phar \
    && wget -O /usr/local/bin/phpcs https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar \
    && wget -O /usr/local/bin/phpcbf https://squizlabs.github.io/PHP_CodeSniffer/phpcbf.phar \
    && chmod +x /usr/local/bin/php*

# install nodejs, npm, yarn and dependencies
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs autoconf automake g++ gcc libtool make nasm python \
    && npm i -g yarn

WORKDIR /var/www/html
CMD composer install && npm install && php ./artisan serve --port=80 --host=0.0.0.0
EXPOSE 80
HEALTHCHECK --interval=1m CMD curl -f http://localhost/ || exit 1
ENV TERM xterm
