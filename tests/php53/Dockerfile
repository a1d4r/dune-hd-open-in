# PHP 5.3.6 CLI, the version of the Dune HD shell (libphp5.so), plus the
# tools build.sh needs. No official php:5.3 image exists, so PHP is built
# from the php.net museum tarball with the extensions plugins may rely on
# that need no external libraries.
#
#   docker build -t dune-php53 tests/php53
#   docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w dune-php53 \
#       sh build.sh filmix_api_supplier
FROM debian:bookworm-slim

ARG PHP_VERSION=5.3.6
ARG PHP_SHA256=30ae880f22e3ee93eccc9b80e3c58b0d6364d139bb4366dcc27f2fab658d3198

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      dash mksh shellcheck zip unzip python3 \
      ca-certificates curl bzip2 gcc make libc6-dev autotools-dev \
 && curl -fsSL -o /tmp/php.tar.bz2 "https://museum.php.net/php5/php-$PHP_VERSION.tar.bz2" \
 && echo "$PHP_SHA256  /tmp/php.tar.bz2" | sha256sum -c - \
 && mkdir /tmp/php \
 && tar -xjf /tmp/php.tar.bz2 -C /tmp/php --strip-components=1 \
 && cd /tmp/php \
 # config.guess of 2011 does not know aarch64 (Apple Silicon hosts).
 && cp /usr/share/misc/config.guess /usr/share/misc/config.sub . \
 # gnu89 and -fcommon: old C that modern gcc rejects by default.
 && CFLAGS="-O2 -std=gnu89 -fcommon" ./configure --prefix=/usr/local \
      --disable-all --disable-cgi \
      --enable-json --enable-mbstring --enable-ctype --enable-hash \
      --enable-filter --enable-tokenizer --enable-session \
 && make -j"$(nproc)" \
 && make install-cli \
 && cd / \
 && rm -rf /tmp/php /tmp/php.tar.bz2 \
 && apt-get purge -y --auto-remove curl bzip2 gcc make libc6-dev autotools-dev \
 && rm -rf /var/lib/apt/lists/* \
 && php -v
