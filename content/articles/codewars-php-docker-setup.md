---
title: "PHP environment for Codewars Kata challenges"
author: "Ally"
summary: "Relatively barebones PHP environment for Codewars Kata challenges, with `xdebug`."
publishDate: 2020-08-31T00:00:00+01:00
tags: ['docker', 'php', 'xdebug', 'kcachegrind']
---

[`codewars`](https://www.codewars.com/users/alistaircol) is a site with loads of [kata](https://en.wikipedia.org/wiki/Kata_(programming)) challenges that I have been engrossed in for a couple of weeks now.

[![badge](https://www.codewars.com/users/alistaircol/badges/large)](https://www.codewars.com/users/alistaircol)

You are given a description of the task as well as very basic code stubs and a few test scenarios. It is your job to write the code to complete the task and tests pass.

However, you might want to use an IDE (and a debugger) since some of the tasks can get quite tricky. I needed to get out the debugger and profiler for [Simple assembler interpreter](https://www.codewars.com/kata/58e24788e24ddee28e000053).

Repo is here: https://github.com/alistaircol/codewars-php7.0

---

#### `Makefile`

Just some handy shortcuts for building image and running some commands.

We will use `composer` to install `phpunit`, you might need to create a token, for creating a Github token for `composer` to use, read [here](https://www.previousnext.com.au/blog/managing-composer-github-access-personal-access-tokens).

```makefile
.PHONY: build

build:
	docker build --no-cache --tag ac93_codewars:7.0 .
	${exec} composer require --dev phpunit/phpunit

exec = docker run \
	--init \
	--interactive \
	--tty \
	--rm \
	--user $$(id -u) \
	--env COMPOSER_AUTH='{"github-oauth": {"github.com": ""}}' \
	--volume "$$(pwd):/app" \
	--workdir /app \
	ac93_codewars:7.0

ci:
	${exec} composer install

shell:
	${exec} bash

run:
	${exec} $(args)

app:
	${exec} php src/index.php

test:
	${exec} bash -c "./vendor/bin/phpunit $(args)"
```

#### `Dockerfile`

Since I am a PHP guy, the Kata's offer the choice of PHP 7.0 or 7.4. The task I needed to debug was 7.0 only so this `Dockerfile` reflects that. Altering the Dockerfile to be 7.4 is trivial, just change the base image and look in PECL for a suitable more recent `xdebug` release.

```dockerfile
FROM php:7.0-apache
RUN yes | pecl install xdebug-2.6.1 \
    && apt-get update \
    && apt-get install -y nano git zip

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
COPY 99-xdebug.ini /usr/local/etc/php/conf.d
``` 

#### Configuring `xdebug`

For `zend_extension`, you might want to run `$(find /usr/local/lib/php/extensions/ -name xdebug.so)` in the container and update `99-xdebug.ini` with that. I had some issues.

Update `xdebug.remote_host` using your LAN IP, `ip addr show` or similar.

`99-xdebug.ini`:

```ini
zend_extension=/usr/local/lib/php/extensions/no-debug-non-zts-20151012/xdebug.so
xdebug.idekey=docker
xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_port=9000
xdebug.remote_autostart=1
xdebug.remote_host=192.168.1.6
xdebug.profiler_enable=0
xdebug.profiler_output_dir=/app/xdebug-profiler
; https://xdebug.org/docs/all_settings#trace_output_name
xdebug.profiler_output_name=callgrind.trace-%t.out
```

Update `xdebug.profiler_enable` if you want to use `kcachegrind` or similar.

![kcachegrind](/img/articles/codewars-php-setup/kcachegrind.png)

For any of these changes to take effect, run `make` again.

#### Configuring `phpunit`

`phpunit.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit backupGlobals="false"
         backupStaticAttributes="false"
         colors="true"
         convertErrorsToExceptions="true"
         convertNoticesToExceptions="true"
         convertWarningsToExceptions="true"
         bootstrap="./src/index.php"
         processIsolation="false"
         stopOnFailure="false">
    <testsuites>
        <testsuite name="Application Test Suite">
            <directory>./tests/</directory>
        </testsuite>
    </testsuites>
    <filter>
        <whitelist>
            <directory suffix=".php">src/</directory>
        </whitelist>
    </filter>
</phpunit>
```

Fairly simple, `bootstrap` `./src/index.php` since this will be the main code.

#### Coding

* Code in `src/index.php`
* Tests in `tests/`

Run `make app` to run the app (might need to add call in the source to the function).

Run `make test` to run test suite.

Run `make shell` to just get into the box and look around. 
