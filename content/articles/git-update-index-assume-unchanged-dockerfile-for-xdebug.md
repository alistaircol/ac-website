---
title: "Use git feature to 'hide' local changes of a Dockerfile which installs xdebug"
author: "Ally"
summary: "Use `git update-index --assume-unchanged` to remove local changes of a `Dockerfile` from the staging area in a repository, and use (an ignored) `docker-compose.override.yml` to configure `xdebug`."
publishDate: 2022-10-11T19:10:18+0100
tags: ['docker','xdebug','git']
---

If you're working on a team and want to make some very specific changes to your local development environment then `git update-index --assume-unchanged` (and some `gitignore` later on) might be for you.

## Docker Services

`docker-compose.yml`:

```yaml
---
version: '3.7'
services:
  php:
    container_name: my_php
    build:
      context: .
      dockerfile: Dockerfile
```

The team uses the following base image.

`Dockerfile`:

```dockerfile
FROM php:8.1-fpm
```

Build and run the container:

```bash
docker-compose build php
docker-compose up -d
cat <<EOF | docker exec -i my_php bash
(php -m | grep -i 'xdebug') && echo 'xdebug is installed' || echo 'xdebug is not installed'
EOF
```

Output:

```text
xdebug is not installed
```

<center>

![No xdebug?](/img/articles/git-update-index-xdebug-docker/no-xdebug.jpg)

</center>

## `Dockerfile` changes

I added the following to `Dockerfile`:

```dockerfile
RUN pecl install xdebug-3.1.5 \
    && docker-php-ext-enable xdebug
```

Build and run the container:

```bash
docker-compose stop
docker-compose build php
docker-compose up -d
cat <<EOF | docker exec -i my_php bash
(php -m | grep -i 'xdebug') && echo 'xdebug is installed' || echo 'xdebug is not installed'
EOF
```

Output:

```text
xdebug
Xdebug
xdebug is installed
```

<center>

![xdebug](/img/articles/git-update-index-xdebug-docker/yes-xdebug.jpeg)

</center>

## Ignoring `Dockerfile` changes

Running `git status` after adding the `RUN` command to install and enable `xdebug`:

```text
$ git status
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	      modified:   Dockerfile

no changes added to commit (use "git add" and/or "git commit -a")
```

Then to ignore the file with [`git update-index`](https://git-scm.com/docs/git-update-index#Documentation/git-update-index.txt---no-assume-unchanged):

```bash
git update-index --assume-unchanged Dockerfile
```

Running `git status` again:

```text
$ git status
On branch main
nothing to commit, working tree clean
```

If you change your mind and want to commit some changes:

```bash
git update-index --no-assume-unchanged Dockerfile
```

```text
$ git status
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   Dockerfile

no changes added to commit (use "git add" and/or "git commit -a")
```

## Configuring `xdebug` with `docker-compose.override.yml`

I created a few `xdebug.ini` files:

{{<accordion title="`99-xdebug-no-trigger-ide-key.ini`">}}
```ini
xdebug.mode = "debug"
# alternatively host.docker.internal
xdebug.client_host = "docker.for.mac.localhost"
xdebug.client_port = "9003"
xdebug.idekey = "PHPSTORM"
xdebug.max_nesting_level = 200
xdebug.start_with_request = "yes"
```
{{</accordion>}}

{{<accordion title="`99-xdebug-no-trigger-no-ide-key.ini`">}}
```ini
xdebug.mode = "debug"
# alternatively host.docker.internal
xdebug.client_host = "docker.for.mac.localhost"
xdebug.client_port = "9003"
xdebug.idekey = ""
xdebug.max_nesting_level = 200
xdebug.start_with_request = "yes"
```
{{</accordion>}}

{{<accordion title="`99-xdebug-trigger-ide-key.ini`">}}
```ini
xdebug.mode = "debug"
# alternatively host.docker.internal
xdebug.client_host = "docker.for.mac.localhost"
xdebug.client_port = "9003"
xdebug.idekey = "PHPSTORM"
xdebug.max_nesting_level = 200
xdebug.start_with_request = "trigger"
```
{{</accordion>}}

{{<accordion title="`99-xdebug-trigger-no-ide-key.ini`">}}
```ini
xdebug.mode = "debug"
# alternatively docker.for.mac.localhost
xdebug.client_host = "docker.for.mac.localhost"
xdebug.client_port = "9003"
xdebug.idekey = ""
xdebug.max_nesting_level = 200
xdebug.start_with_request = "yes"
```
{{</accordion>}}

Create a `docker-compose.override.yml` so we can mount additional config files into the container.

`docker-compose.override.yml`:

```yaml
---
version: '3.7'
services:
  php:
    volumes:
    - ./99-xdebug-trigger-ide-key.ini:/usr/local/etc/php/conf.d/99-xdebug-trigger-ide-key.ini:ro
```

Verify by using `docker-compose config`:

```yaml
name: ac_website_article
services:
  php:
    build:
      context: /Users/alistaircollins/development/ac_website_article
      dockerfile: Dockerfile
    container_name: my_php
    networks:
      default: null
    volumes:
    - type: bind
      source: /Users/alistaircollins/development/ac_website_article/99-xdebug-trigger-ide-key.ini
      target: /usr/local/etc/php/conf.d/99-xdebug-trigger-ide-key.ini
      read_only: true
      bind:
        create_host_path: true
networks:
  default:
    name: ac_website_article_default
```

## Ignoring `docker-compose.override.yml` files

There are a couple of methods:

* Best method: add `docker-compose.override.yml` to file from `git core.excludesfile` for all repositories, or
* Alternative method: add `docker-compose.override.yml` to `.git/info/exclude` on a per-repository basis

### Best method

If `git core.excludesfile` does not have a value, I suggest making `~/.gitignore` and then use this path to set the `core.excludesfile` setting in `git`.

```bash
git core.excludesfile ~/.gitignore
```

### Alternative method

Manually add `docker-compose.override.yml` to `.git/info/exclude`, or:

```bash
cat <<EOF >> .git/info/exclude
docker-compose.override.yml
EOF
```
