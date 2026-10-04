# PHP 5.3.6 CLI, the version of the Dune HD shell (libphp5.so), plus the
# tools build.sh needs. No official php:5.3 image exists, so PHP is built
# from the php.net museum tarball with the extensions plugins may rely on
# that need no external libraries. The tarball has a Wayback Machine copy
# (same sha256) as a fallback for the museum.
#
#   docker build -t dune-php53 tests/php53
#   docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w dune-php53 \
#       sh build.sh play_in_apps
FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

ARG PHP_VERSION=5.3.6
ARG PHP_SHA256=30ae880f22e3ee93eccc9b80e3c58b0d6364d139bb4366dcc27f2fab658d3198

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      dash mksh shellcheck zip unzip python3 \
      ca-certificates curl bzip2 gcc make libc6-dev autotools-dev \
 && for url in "https://museum.php.net/php5/php-$PHP_VERSION.tar.bz2" \
      "https://web.archive.org/web/20140704094206id_/http://museum.php.net/php5/php-$PHP_VERSION.tar.bz2"; \
    do \
      curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --connect-timeout 30 \
        -o /tmp/php.tar.bz2 "$url" \
      && echo "$PHP_SHA256  /tmp/php.tar.bz2" | sha256sum -c - \
      && break; \
      rm -f /tmp/php.tar.bz2; \
    done \
 && test -f /tmp/php.tar.bz2 \
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
