---
title: "Developing in PHP with Docker: one nginx ingress to isolated httpd & php containers"
author: "Ally"
summary: "One ingress `nginx` reverse proxy to multiple `php:apache` containers with different (XDebug) configurations."
publishDate: 2020-01-19T00:00:00+01:00
tags: ['docker', 'nginx', 'apache', 'httpd', 'php', 'xdebug', 'mysql']
draft: false
toc: true
---

**TL;DR:**

* All PHP apps running in a single container on port 8080, debugging is sometimes hard.

This can't go on, I need xDebug to work properly!

* Make a base image for all apps to use, isolating each application into its own container.
* Make an `nginx` reverse proxy to route requests to the relevant container.
* For each application, from the base image make a new service with bespoke configuration.

Ahh, debugging is nicer now!* [repo](https://github.com/alistaircol/docker-nginx-ingress-httpd-php)

---

# Motivation

> Improve document quality in 4 minutes with Architectural decision records

>> [dev.to article](https://dev.to/napicella/improve-documentation-quality-in-4-minutes-with-architectural-decision-records-g0h)

> This is a great idea to clarify technical decisions. As covers, we document code religiously. The reasoning behind the processes and solutions, not so much.

> So many times I've looked at code (usually my own) and wondered what the thinking was behind doing something a certain way.

>> Colleague

# Rationale

For some time I've been developing using one container to host **ALL** our (PHP) code for our services, which consists of 3 main projects:

* Core CRM System
* API
* Members Area

It's all bundled into a `php:7-apache` container with some extra things. It works fine, but there's one main reason I was looking to separate things out: debugging.

Debugging Core CRM System was fine, it's where we spend most of our development time, and somewhere around 70% of the time it's not a problem to debug because it's standalone.

If we want to debug something where we use the our Members platform which goes through the API and ultimately to the CRM it plays havoc.

I've spent alot of time searching but the requests just hang. Yes I know Postman, etc. exist, no, I don't want to mock requests, etc. everything I tried in PHPStorm, VS Code didn't seem to work nicely. I had to change the setup because I can't go back to `var_dump` and `echo` debugging!

# nginx

We'll start with `nginx`. This will act as the only ingress point (on port 8080) for our applications. It will act as a reverse proxy to the relevant (isolated) container where the app lives. We can do this based on the server name, e.g.:

* `local-crm.ac93.uk` requests are handled by app in `ac_crm` container.
* `local-api.ac93.uk` requests are handled by app in `ac_api` container.
* `local-mem.ac93.uk` requests are handled by app in `ac_mem` container.
* everything else in `ac_misc` container.

We'll have a config:

* `containers/ingress/sites.conf:/etc/nginx/conf.d/site.conf` 

```nginx
server {
    listen 80;
    server_name local-crm.ac93.uk;

    location / {
        proxy_pass http://ac_crm;
        proxy_set_header Host $host:8080;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name local-api.ac93.uk;

    location / {
        proxy_pass  http://ac_api;
        proxy_set_header Host $host:8080;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name local-mem.ac93.uk;
    server_name local-vip-mem.ac93.uk;

    location / {
        proxy_pass  http://ac_mem;
        proxy_set_header Host $host:8080;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

# everything else
server {
    listen 80 default_server;

    location / {
        proxy_pass  http://ac_misc;
        proxy_set_header Host $host:8080;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

```

A couple things to mention here:

* The [`proxy_pass`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass) is using the `container_name` for the desired container/service to handle that request depending on the `server_name` of the request.
* You'll see I'm using [`proxy_set_header`](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header)` Host $host:8080`, there are some variables available to you such as `$server_port` and `$remote_port` but I couldn't get them to work, I think using `$remote_port` would send me back incremented number on each request, but your mileage may vary.

This service in `docker-compose.yml`:

```yaml
web:
    image: nginx:alpine
    container_name: ac_web
    ports:
        - "8080:80"
    volumes:
        - "./containers/reverse-proxy/site.conf:/etc/nginx/conf.d/site.conf"
    depends_on:
        - ac-crm
        - ac-api
        - ac-mem
        - ac_misc
    networks:
        ac:
            ipv4_address: 172.1.1.101
```

Networks are important, I'll mention that in more detail in the next couple of services.

---

Why do you need to go proxy to `httpd` instances I hear you cry? Why don't you use `php:fpm` and configure them as needed?

Our applications have multisite configuration, so certain things need to change depending on the URLs. In `httpd` virtual host configs we are setting environment variable depending on the URL, e.g.:

```text
<VirtualHost *:80>
    ServerName local-mem.ac93.uk
    ServerAlias local-vip-mem.ac93.co.uk
    
    SetEnvIf Host "local-mem.ac93.uk" MULTISITE=standard
    SetEnvIf Host "local-vip-mem.ac93.uk" MULTISITE=vip
    
    ProxyPreserveHost On
    
    <Directory /var/www/html/laravel-app/public>
        Options -Indexes
        # etc.
    </Directory>
</VirtualHost>
```

We could do this in `nginx` but I'm not familiar with it's configuration. My brief research led me to [if is evil](https://www.nginx.com/resources/wiki/start/topics/depth/ifisevil/) and pretty sure setting environment variables as elegant.

# Base Image

We'll use base `php:7.3-apache` container with extra things installed, like `xdebug`, `memcache`, `composer`, Docker in Docker (don't judge, it's development only!) etc.

`containers/web-base/Dockerfile`:

```dockerfile
FROM php:7.3-apache
# install some essential stuff, mostly for composer and general utilities for managing apps
RUN rm -rf /var/lib/apt/lists/partial && rm -rf /var/lib/apt/lists/*
RUN apt-get update  -o Acquire::BrokenProxy="true" -o Acquire::http::No-Cache="true" -o Acquire::http::Pipeline-Depth="0" --fix-missing
RUN apt-get install -o Acquire::BrokenProxy="true" -o Acquire::http::No-Cache="true" -o Acquire::http::Pipeline-Depth="0" -y \
    zip \
    unzip \
    apt-utils \
    nano \
    curl \
    pv \
    git \
    libzip-dev \
    zlibc \
    zlib1g \
    libmemcached-dev \
    netcat \
    libmagickwand-dev

# install php extensions
RUN docker-php-ext-configure zip --with-libzip
RUN docker-php-ext-install zip

RUN pecl install \
    igbinary-3.0.1 \
    msgpack-2.0.3 \
    imagick-3.4.4 \
    memcached-3.1.3 \
    xdebug-2.7.2

RUN docker-php-ext-enable \
    memcached \
    imagick \
    xdebug

RUN docker-php-ext-install \
    pdo \
    pdo_mysql

#RUN echo "extension=memcached.so" >> /usr/local/etc/php/conf.d/memcached.ini
RUN . /etc/apache2/envvars
RUN a2enmod rewrite
RUN a2enmod proxy_http
RUN usermod -u 1000 www-data

# https://github.com/docker-library/php/issues/344#issuecomment-364843883
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
COPY --from=docker:latest /usr/local/bin/docker /usr/local/bin/docker
```

It's a bit bloated, it's bundled for ease of development and not for lightweight production instances, so bear this in mind.

Docker in Docker is a requirement for our complicated test setup. Maybe I'll write about this another time.

We basically use this image for our 3 projects, and mount volumes. Mostly `php` configs, `httpd` configs, and our source code.

# CRM

So our CRM is the guts of the business.

As mentioned above, it's going to use the base image we mentioned earlier. We're going to mount the code to the container, along with bespoke configuration.

Here is the CRM service in `docker-compose.yml`:

```yaml
ac-crm:
    build:
        context: ./containers/base
    image: ac_web_base:latest
    container_name: ac_crm
    env_file:
        - ./containers/.env
    volumes:
        - "/var/run/docker.sock:/var/run/docker.sock"
        - "./containers/crm/httpd/crm.conf:/etc/apache2/sites-enabled/crm.conf"
        - "./containers/crm/php/crm.ini:/usr/local/etc/php/conf.d/99-crm.ini"
        - "./html/crm:/var/www/html/crm"
    networks:
        ac:
            ipv4_address: 172.1.1.102
```

`build` and `context` are for the base image earlier. If it's not built then it will be soon, and given the name in `image`. The subsequent services (api and members area) refer to the image name too, so it will be reused.

`env_file` is common stuff used in all application services, it's not really essential for this article, but we have DB info in there. I'm omitting database stuff for simplicity here.

`volumes`: 

* The first in is for Docker in Docker, this is not essential.
* The second entry in is bespoke configuration for apache virtual host.
* The third entry in is bespoke configuration for PHP (mostly XDebug).
* The fourth entry is our code.

## Apache Config

Just a relatively straightforward config.

Note that [`ProxyPreserveHost`](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html#proxyreceivebuffersize) is `On`, this is required for the request to get sent back correctly to the client. This is the `proxy_set_header Host $host:8080;` part in the ingress service.

The file `containers/crm/httpd/crm.conf` will look something like this:

```text
<VirtualHost *:80>
    ServerName local-crm.ac93.uk
    DocumentRoot /var/www/html/crm
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    ProxyPreserveHost On

    <Directory /var/www/html/crm>
        Options -Indexes
    </Directory>
</VirtualHost>
```

## PHP Config

The file `containers/crm/php/crm.ini` will look something like this:

```ini
[global]
; https://github.com/docker-library/php/issues/212#issuecomment-204817907
log_errors = On
error_log = /dev/stderr
error_reporting = E_ALL
display_errors = stderr

xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_port=9100
xdebug.remote_autostart=1
xdebug.remote_host=192.168.1.6
```

So the flow sort of looks like this:

![CRM Debugging](/img/articles/docker-nginx-apache/debug-crm.png)

Unfortunately for each project you will need to update the `remote_host` to the IP of your host machine where your debugger is running.

# API

Here is the API service in `docker-compose.yml`:

```yaml
ac-api:
    build:
        context: ./containers/base
    image: ac_web_base:latest
    container_name: ac_api
    env_file:
        - ./containers/.env
    volumes:
        - "./containers/api/httpd/api.conf:/etc/apache2/sites-enabled/api.conf"
        - "./containers/api/php/api.ini:/usr/local/etc/php/conf.d/api.ini"
        - "./html/api:/var/www/html/api"
    depends_on:
        - ac-crm
    networks:
        ac:
            ipv4_address: 172.1.1.103
    extra_hosts:
        - "local-crm.ac93.uk:172.1.1.102"
```

This looks familiar by now.

Main thing to note here is that there is an extra section; `extra_hosts`. We need this because our API can call our CRMs API, so it needs to know how to find the CRM.

The virtual host setup is much the same, `containers/api/httpd/api.conf`:

```text
<VirtualHost *:80>
    ServerName local-api.ac93.uk
    DocumentRoot /var/www/html/api
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    
    ProxyPreserveHost On

    <Directory /var/www/html/api>
        Options -Indexes
    </Directory>
</VirtualHost>

```

Same thing with the `php` config, only thing really changing is the `xdebug.remote_port`.

`containers/api/php/api.ini`:

```ini
[global]
; https://github.com/docker-library/php/issues/212#issuecomment-204817907
log_errors = On
error_log = /dev/stderr
error_reporting = E_ALL
display_errors = stderr

xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_port=9101
xdebug.remote_autostart=1
xdebug.remote_host=192.168.1.6

```

# Members Area

Last piece of the puzzle and nothing much changes here.

The service in `docker-compose.yml`:

```yaml
ac-mem:
    build:
        context: ./containers/base
    image: ac_web_base:latest
    container_name: ac_mem
    env_file:
        - ./containers/.env
    volumes:
        - "./containers/mem/httpd/mem.conf:/etc/apache2/sites-enabled/mem.conf"
        - "./containers/mem/php/mem.ini:/usr/local/etc/php/conf.d/mem.ini"
        - "./html/mem:/var/www/html/mem"
    depends_on:
        - ac-api
    networks:
        ac:
            ipv4_address: 172.1.1.104
    extra_hosts:
        - "local-api.ac93.uk:172.1.1.103"
```

Like how the API needs to know how to find the CRM, the Members Area needs to know how to find the API, thanks `extra_hosts`.

Apache config is very similar `containers/mem/httpd/mem.conf`:

```text
<VirtualHost *:80>
    ServerName local-mem.ac93.uk
    ServerAlias local-vip-mem.ac93.uk

    DocumentRoot /var/www/html/mem
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    ProxyPreserveHost On

    <Directory /var/www/html/mem>
        Options -Indexes
    </Directory>
</VirtualHost>
```

Same again with PHP config `containers/mem/php/mem.ini`:

```ini
[global]
; https://github.com/docker-library/php/issues/212#issuecomment-204817907
log_errors = On
error_log = /dev/stderr
error_reporting = E_ALL
display_errors = stderr

xdebug.remote_enable=1
xdebug.remote_handler=dbgp
xdebug.remote_port=9102
xdebug.remote_autostart=1
xdebug.remote_host=192.168.1.6
```

That's all for now! I didn't go into detail about the `ac_misc` container because it's the same story. Instructions are below on how to setup the debugger in PHPStorm.

![Docker Compose Logs](/img/articles/docker-nginx-apache/overview.png)

To see a complete example, see the associated github repo [https://github.com/alistaircol/docker-nginx-ingress-httpd-php](https://github.com/alistaircol/docker-nginx-ingress-httpd-php).

# Setting Up Debugger

## (PHPStorm)

Each project will need to be configured.

Go to `File -> Settings -> Language & Frameworks -> PHP`

* Set PHP language level/version
* Add a new CLI interpreter
  * Select `From Docker, Vagrant, VM, Remote...`

![PHPStorm Step 01](/img/articles/docker-nginx-apache/phpstorm/01a.png)

Choose `Docker` and `php:7.3-apache` as the image name.

![PHPStorm Step 01](/img/articles/docker-nginx-apache/phpstorm/01.png)

![PHPStorm Step 02](/img/articles/docker-nginx-apache/phpstorm/02.png)

Now we need tell PHPStorm where to find files locally based on the file location on the server.

![PHPStorm Step 03](/img/articles/docker-nginx-apache/phpstorm/03.png)

![PHPStorm Step 04](/img/articles/docker-nginx-apache/phpstorm/04.png)

![PHPStorm Step 05](/img/articles/docker-nginx-apache/phpstorm/05.png)

Go to `File -> Settings -> Language & Frameworks -> PHP -> Debug`

Set the Debug port to 9100 or whatever it is for your project. Uncheck the two force checkboxes.

![PHPStorm Step 06](/img/articles/docker-nginx-apache/phpstorm/06.png)

Go to `File -> Settings -> Language & Frameworks -> PHP -> Servers`

Add a new Server and give it a meaningful name.

Set the `Host` to the IP address on which PHPStorm is running and `Port` to that which the project XDebug is configured to.

![PHPStorm Step 07](/img/articles/docker-nginx-apache/phpstorm/07.png)

Go to `Run -> Edit Configurations`.

Add a new `PHP Remote Debug` configuration.

![PHPStorm Step 08](/img/articles/docker-nginx-apache/phpstorm/08.png)

Check `Filter debug connection by IDE Key` and select your server.

![PHPStorm Step 09](/img/articles/docker-nginx-apache/phpstorm/09.png)

Run the debug configuration, set a breakpoint and hit it!

![PHPStorm Step 10](/img/articles/docker-nginx-apache/phpstorm/10.png)


<link rel="stylesheet" href="/css/ac.css" />
