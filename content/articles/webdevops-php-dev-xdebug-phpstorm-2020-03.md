---
title: "Using webdevops/php-dev:7.x and configuring xDebug 3 for local development in PHPStorm"
author: "Ally"
summary: "How to set up PHPStorm, and use `webdevops/php-dev:7.x` image using `xdebubg` v3."
publishDate: 2020-12-18T12:00:00+01:00
tags: ['php', 'docker', 'xdebug']
---

![make rule for local dev with xdebug](/img/articles/xdebug3-webdevops-phpstorm/hero.png)

With the relatively recent release of xDebug 3 (late November 2020) - there were some major config changes!

My previous go-to configuration for xDebug using the `webdevops/php-dev:7.3` image:

`.env` file loaded in `docker-compose` but would work in `docker run`:

```dotenv
PHP_DEBUGGER=xdebug
XDEBUG_REMOTE_AUTOSTART=1
XDEBUG_REMOTE_CONNECT_BACK=0
XDEBUG_REMOTE_HOST=192.168.1.6
XDEBUG_IDE_KEY=phpstorm
XDEBUG_REMOTE_PORT=9000
```

## PHP 7.4

Recently started using version 7.4 and this image uses xDebug 3, which includes some significant [changes](https://xdebug.org/docs/upgrade_guide).

The equivalent `.env` file to get the same end result from the previous version is:

```dotenv
PHP_DEBUGGER="xdebug" \
XDEBUG_MODE="develop,debug" \
XDEBUG_CLIENT_HOST="192.168.1.6" \
XDEBUG_CLIENT_PORT="9003" \
XDEBUG_IDE_KEY="phpstorm" \
XDEBUG_SESSION="phpstorm" \
XDEBUG_START_WITH_REQUEST="yes" \
```

That's pretty much it.

Setting up xDebug in PHPStorm is pretty straightforward. I have an old [article](https://ac93.uk/articles/docker-nginx-httpd-php-mysql/) on that (planning on updating it).

---

Configure debug settings.

![languages and frameworks -> php -> debug](/img/articles/xdebug3-webdevops-phpstorm/phpstorm-01.png)

Add a server with path maps.

<center>

![languages and frameworks -> php -> servers](/img/articles/xdebug3-webdevops-phpstorm/phpstorm-02.png)

</center>

Add a run configuration.

![add remote debug run configuration](/img/articles/xdebug3-webdevops-phpstorm/phpstorm-03.png)
