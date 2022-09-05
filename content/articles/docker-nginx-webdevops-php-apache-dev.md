---
title: "Better developing in PHP with Docker: one nginx ingress to isolated httpd & php containers"
author: "Ally"
summary: "One ingress `nginx` reverse proxy to multiple `webdevops/apache-php-dev` containers with different (XDebug) configurations."
publishDate: 2020-11-30T00:00:00+01:00
tags: ['docker', 'nginx', 'apache', 'httpd', 'php', 'xdebug', 'mysql']
draft: true
---

Fairly standard ingress:

`docker-compose.yml`:

```yaml
version: '3'
services:
    web:
        image: nginx:alpine
        ports:
            - '8080:80'
        volumes:
            - './nginx.conf:/etc/nginx/conf.d/nginx.conf'
```

`nginx` config could have multiple `server` blocks (or `http`) to each individual container.

`nginx.conf`:

```apacheconfig
server {
    listen 80;
    server_name local-api.ac93.uk;

    location / {
        proxy_pass http://container_name;
        proxy_set_header Host $host:8080; # couldn't get server_port or remote_port to work
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

I have a standard `web.env` for some config for our apps and some environemnt settings for `webdevops/apache-php-dev` containers.

`web.env`:

```
# https://dockerfile.readthedocs.io/en/latest/content/DockerImages/dockerfiles/php-apache-dev.html
PHP_DEBUGGER=xdebug
XDEBUG_REMOTE_AUTOSTART=1
XDEBUG_REMOTE_CONNECT_BACK=0
XDEBUG_REMOTE_HOST=192.168.1.6
XDEBUG_IDE_KEY=docker
# our apps
MYSQL_HOST=db
MYSQL_USER=root
MYSQL_PASS=password
```

And a `.env` file for each container, i.e. `api.env`.

`api.env`:

```
# https://dockerfile.readthedocs.io/en/latest/content/DockerImages/dockerfiles/php-apache-dev.html
WEB_DOCUMENT_ROOT=/var/www/html/api/public
XDEBUG_REMOTE_PORT=9101
```

Adding the `*.env` files to the container.

```yaml
api:
    build:
        context: .
    image: web_base:latest
    container_name: ac_api
    env_file:
        - web.env
        - api.env
```

---

Virtualhost snafu.

HTTP basic auth isn't received by this image by default. This issue is resolved by adding the following rewrite rule to the virtual host [here](https://github.com/tuupola/slim-basic-auth/issues/74#issuecoment-412785865).

```apacheconfig
RewriteRule .* - [env=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
``` 

TODO: show this issue.

```yaml
volumes:
    - './api.conf:/opt/docker/etc/httpd/vhost.common.d/api.conf'
```

Logging to syslog! amazing!

```yaml
docker run --rm -it -v $(pwd):/data cytopia/yamllint
```

Github workflow:

```yaml


---
name: CI
'on':
  pull_request:
  push:
    branches:
      - master
  schedule:
    - cron: "30 6 * * 4"
jobs:

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - name: Check out the codebase.
        uses: actions/checkout@v2
        with:
          path: 'geerlingguy.php-versions'

      - name: Set up Python 3.
        uses: actions/setup-python@v2
        with:
          python-version: '3.x'

      - name: Install test dependencies.
        run: pip3 install yamllint ansible-lint

      - name: Lint code.
        run: |
          yamllint .
          ansible-lint
```
