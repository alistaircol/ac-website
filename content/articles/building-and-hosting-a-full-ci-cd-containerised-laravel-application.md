---
title: "Building and hosting a full CI & CD containerised Laravel application"
author: "Ally"
summary: "I've hosted many apps. I've set up CI to build containers. But I've never figured out the continuous deployment part, until now."
publishDate: 2021-12-04T12:00:00+01:00
tags: ['github', 'ci', 'cd', 'traefik', 'watchtower']
draft: true
---

In this post I will explain in broad strokes how I develop and deploy a Laravel application and then set up CI & CD for it.

The application CI pipeline will:

* Run some basic code checks
* Build front-end asset (css & js) bundles
* Build container for entire application (excluding dev dependencies and including front-end bundles)

The resultant container will:

* Run web application (obviously)
* Run scheduled tasks (i.e. `php artisan schedule:work`)
* Consume queued jobs (i.e. `php artisan queue:work`)

---

I'm using github workflows and its private package registry, so this might not be for you. Hopefully there will still be some useful things, though.

## Overview 

Everything will be running as a `docker` container:

* `traefik` - a reverse proxy and the main entry point into the services
    * The advantage of `traefik` is that you can refer to a container, at least in my implementation, by a FQDN. No more assigning/remembering random ports.
* `bnss-app` - my Laravel application, it needs a `redis` cache, a `mysql` database and it will use `imgproxy`
* `redis` - just a simple cache for my application
* `database` - just a `mysql` database
* `imgproxy` - my application will work with images, `imgproxy` allows for easy manipulation

Some other services I will use (not essential for my application to function) but might not explain:

* `portainer` - gives insight and control over `docker` services on the server - I rarely use this
* `dozzle` - a nice web UI to see logs from all `docker` services
* `watchtower` - a really handy tool to (automatically, by polling; or by webhook) detect change to the containers image and 'restart' the service, running the latest version

I won't detail all of these services, it's just the ones I have chosen to use for my use-case.

## Repositories

I have two repositories:

* `bnss` - my applications `docker-compose` files, `ansible` playbooks, `terraform` scripts, etc.
  * `ansible` playbooks to install essential software on server, install crons, etc.
  * `terraform` to set up S3 bucket
* `bnss-app` - my application code
  * `Dockerfile`
  * `github/workflows/*.yaml` files for CI & CD pipeline

These are separate for a couple of simple reasons:

* changes to `docker-compose`, `ansible`, `terraform` files shouldn't trigger a build when pushed since they have different deployment characteristics
  * at the moment I have not automated this, I have to `ssh` and `git pull` these, and then restart the containers
* ignoring these `docker-compose`, `ansible`, `terraform` files in the workflow would be difficult
* it keeps each repository more focussed and clean

## `docker-compose` files

I have separate `docker-compose` files for each service:

```text
$ tree -L 1 .
.
├── acme.json
├── ansible/
├── docker-compose.bnss-app.override.yaml
├── docker-compose.bnss-app.yaml
├── docker-compose.database.yaml
├── docker-compose.dozzle.yaml
├── docker-compose.imgproxy.yaml
├── docker-compose.portainer.yaml
├── docker-compose.redis.yaml
├── docker-compose.watchtower.yaml
├── docker-compose.yaml
├── Makefile
├── README.md
└── terraform/
```

Each `docker-compose*.yaml` file is anticipated to be used in production environment.

There are some `docker-compose*.override.yaml` files that are used in development environment.

For example, `docker-compose.bnss-app.override.yaml` will change the `image` from the production image to a development PHP image and mount a volume for code.

Why have separate files? I hear you ask. Well:

Pros:

* you don't need to search a massive file for a service you need to change
* `diff`s are much more digestible

Cons:

* having separate `docker-compose*.yaml` files makes orchestration a little more verbose

---

I'm hosting a lot of these services instead of using other managed services mainly to reduce cost, and the fact this is still a WIP application and there's no requirement for HA, etc.

---

`docker-compose` by default will load `docker-compose(\.override)?\.y[a]?ml` files. This means for all our services to be loaded we will need to specify more files by `-f` manually.

You could do (and I have done) something like this:

```makefile
docker_compose = docker-compose \
		-f docker-compose.yaml \
		-f docker-compose.traefik.yaml \
		-f docker-compose.mailhog.yaml \
		-f docker-compose.portainer.yaml \
		-f docker-compose.mongo.yaml \
		-f docker-compose.rabbitmq.yaml \
		-f docker-compose.mysql8.yaml \
	
up:
   @${docker_compose} up
```

But this means you have to remember to add this file to the command.

I resolved this issue (it's not pretty, I've left comments in):

```makefile
# depending on the hostname we're running on this 
ifndef HOSTNAME
HOSTNAME := $(shell hostname)
endif

# my dev pc hostname is pc, if running from here assume I want to include override files
ifeq ($(HOSTNAME),pc)
INCLUDE_OVERRIDE_FILES = true
endif

space = $(eval) $(eval)
docker_compose_files = $(filter-out $(wildcard docker-compose*.override.yaml), $(wildcard docker-compose*.yaml))
docker_compose_override_files = $(filter $(wildcard docker-compose*.override.yaml), $(wildcard docker-compose*.yaml))

# having docker-compose.yaml files before docker-compose.override.yaml files is important
all_docker_compose_files := $(docker_compose_files)
all_docker_compose_files += $(docker_compose_override_files)

ifneq ($(strip $(INCLUDE_OVERRIDE_FILES)),true)
# in here I add a earning saying that override files are being ignored
# if you need them use INCLUDE_OVERRIDE_FILES=true make
else
docker_compose_files = $(all_docker_compose_files)
endif

docker_compose_files_arg = -f $(subst $(space), -f ,$(docker_compose_files))
docker_compose = docker-compose $(docker_compose_files_arg)

up:
    @$(docker_compose) up
    
upd:
    @$(docker_compose) up -d
```

This means (when `hostname` is `pc`) `make up` or `INCLUDE_OVERRIDE_FILES=true make up` will explicitly load all `docker-compose(\.override)?\.y[a]?ml`, e.g.:

```bash
docker-compose \
  -f docker-compose.yaml \
  -f docker-compose.bnss-members.yaml \
  -f docker-compose.dozzle.yaml \
  -f docker-compose.database.yaml \
  -f docker-compose.portainer.yaml \
  -f docker-compose.imgproxy.yaml \
  -f docker-compose.watchtower.yaml \
  -f docker-compose.redis.yaml \
  -f docker-compose.watchtower.override.yaml \
  -f docker-compose.bnss-members.override.yaml \
  up
```

## Secrets

I'm just using `.env` file. `docker-compose` will read this with any of its commands or any specified with `--env-file`.

Leaving this here with comments so you can see how some of the steps I might not explain.

e.g.:

```dotenv
# docker_config location is needed for watchtower if using a registry that requires authentication
docker_config_location=/home/ally/.docker/config.json
docker_container_name_prefix=bnss_local

# I use cloudflare DNS authentication for traefik to generate TLS certificates
# I use a vanity domain with the naked domain and wildcard subdomains to localhost
cloudflare_api_email=
cloudflare_api_dns_zone_token=

# I use basic auth from traefik (generate using htpasswd) to authwall some sensitive services
# namely portainer, dozzle, admin panels, etc.
traefik_basic_auth_traefik=
traefik_ipwhitelist_source_range="172.0.0.0/8, 192.168.1.0/24"
portainer_ipwhitelist_source_range=${traefik_ipwhitelist_source_range}
portainer_admin_pass=

# I use watchtower in API mode
# the CI/CD workflow will HEAD to this endpoint to update and restart the container
watchtower_notifications_slack_hook_url=
watchtower_notifications_slack_icon_emoji=
watchtower_notifications_slack_identifier=
watchtower_http_api_token=

database_root_password=password

# used echo $(xxd -g 2 -l 64 -p /dev/random | tr -d '\n') to generate these
IMGPROXY_KEY=
IMGPROXY_SALT=
IMGPROXY_SIGNATURE_SIZE=32

# used for imgproxy
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=eu-west-2
```

I would love to learn to use [`vault`](https://www.hashicorp.com/products/vault) instead of this. Coming soon??™

## Traefik

Most examples out on using `traefik` use 'dynamic configuration' that requires specifying a (`yaml` or `toml`) file. But I'm not in to having configuration in two places, so...

I've exclusively used 'static configuration' in the form of labels on the services.

A thing to note about this service and its configuration:

* `${docker_container_name_prefix:-bnss}` if there is `docker_container_name_prefix` in the `env-file` then it will be used, else `bnss`, so if no `env-file` it will be `bnss_traefik`

Tip: you can run (specifying as many files with `-f`) `docker-compose -f docker-compose.yaml config` to see how the interpolation will work.

`docker-compose.yaml`:

```yaml
---
version: "3.9"
services:
  traefik:
    image: traefik:v2.5
    container_name: ${docker_container_name_prefix:-bnss}_traefik
    restart: unless-stopped
    command:
    - --api.insecure=false
    - --api.dashboard=true
    - --api.debug=true
    - --log.level=DEBUG
    - --accesslog=true
    - --providers.docker=true
    - --providers.docker.exposedbydefault=false
    - --entrypoints.http.address=:80
    - --entrypoints.https.address=:443
    - --entryPoints.http.forwardedHeaders.insecure
    - --entryPoints.https.forwardedHeaders.insecure
    - --entrypoints.mysql.address=:3306
    - --certificatesresolvers.mychallenge.acme.tlschallenge=false
    - --certificatesresolvers.mychallenge.acme.httpchallenge=false
    - --certificatesresolvers.mychallenge.acme.dnschallenge=true
    - --certificatesresolvers.mychallenge.acme.dnschallenge.provider=cloudflare
    - --certificatesresolvers.mychallenge.acme.dnschallenge.delaybeforecheck=0
    - --certificatesresolvers.mychallenge.acme.email=${cloudflare_api_email}
    - --certificatesresolvers.mychallenge.acme.storage=/etc/traefik/acme.json
    labels:
    - traefik.enable=true
    - traefik.http.routers.traefik.entrypoints=http
    - traefik.http.routers.traefik.rule=Host(`traefik.${domain_name:-dev.ac93.uk}`)
    - traefik.http.middlewares.traefik-https-redirect.redirectscheme.scheme=https
    - traefik.http.middlewares.sslheader.headers.customrequestheaders.X-Forwarded-Proto=https
    - traefik.http.routers.traefik.middlewares=traefik-https-redirect
    - traefik.http.routers.traefik-secure.entrypoints=https
    - traefik.http.routers.traefik-secure.rule=Host(`traefik.${domain_name:-dev.ac93.uk}`)
    - traefik.http.routers.traefik-secure.tls=true
    - traefik.http.routers.traefik-secure.tls.certresolver=mychallenge
    - traefik.http.routers.traefik-secure.tls.domains[0].main=${domain_name:-dev.ac93.uk}
    - traefik.http.routers.traefik-secure.tls.domains[0].sans=*.${domain_name:-dev.ac93.uk}
    - traefik.http.routers.traefik-secure.service=api@internal
    - traefik.http.routers.traefik-secure.middlewares=traefik-authentication-required@docker
    - traefik.http.middlewares.traefik-authentication-required.basicauth.users=${traefik_basic_auth_traefik}
    ports:
    - 80:80
    - 443:443
    - 3306:3306
    environment:
    - CF_API_EMAIL=${cloudflare_api_email}
    - CF_DNS_API_TOKEN=${cloudflare_api_dns_zone_token}
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./acme.json:/etc/traefik/acme.json
```

The `acme.json` is the TLS certificates and this should be mounted. It's the only generated file on the host that is required.

If you want to follow along you should `touch acme.json` and `chmod 600 acme.json` before starting.

## Database

Just a simple `mysql` service. But an example of a `tcp` router in `traefik`, I'm just restricting its access to certain IP range. 

`docker-compose.database.yaml`:

```yaml
---
version: "3.9"
services:
  database:
    image: mysql:8
    container_name: ${docker_container_name_prefix}_database
    restart: unless-stopped
    environment:
    - MYSQL_ROOT_PASSWORD=${database_root_password}
    - MYSQL_DATABASE=bnss
    volumes:
    - bnss_database:/var/lib/mysql
    labels:
    - traefik.enable=true
    - traefik.tcp.routers.database.entrypoints=mysql
    - traefik.tcp.routers.database.rule=HostSNI(`*`)
    - traefik.tcp.routers.database.service=database
    - traefik.tcp.services.database.loadbalancer.server.port=3306
    - traefik.tcp.routers.database.middlewares=ip-restricted@docker
    - traefik.tcp.middlewares.ip-restricted.ipwhitelist.sourcerange=${traefik_ipwhitelist_source_range:-127.0.0.1/32}

volumes:
  bnss_database:
    driver: local
```

## Watchtower

I'm using this service in `--label-enable=true` mode, which means that it will only update and restart (if applicable) those services with the `com.centurylinklabs.watchtower.enable=true` label.

It's also running in `--http-api-update` mode, meaning an authenticated `HEAD` to `/v1/update` will trigger the check to see if new image is available and download and restart the service.

One thing to note is that this is synchronous, so your http call in your pipeline may need to increase timeout as this will only return a response once the image has been downloaded and restarted on remote. This will keep your pipeline running so you may wish to come up with another solution if this is taking too long.

`docker-compose.watchtower.yaml`:

```yaml
---
version: "3.9"
services:
  watchtower:
    image: containrrr/watchtower
    container_name: ${docker_container_name_prefix}_watchtower
    restart: unless-stopped
    command:
    - --debug
    - --cleanup
    - --http-api-update
    - --http-api-token=${watchtower_http_api_token}
    - --no-startup-message
    - --label-enable=true
    - --notifications=slack
    - --notification-slack-hook-url=${watchtower_notifications_slack_hook_url}
    - --notification-slack-icon-emoji=${watchtower_notifications_slack_icon_emoji:-:)}
    - --notification-slack-identifier=${watchtower_notifications_slack_identifier:-BNSS Local}
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ${docker_config_location:-/root/.docker/config.json}:/config.json
    labels:
    - traefik.enable=true
    - traefik.http.routers.watchtower.entrypoints=http
    - traefik.http.routers.watchtower.rule=Host(`watchtower.${domain_name:-dev.ac93.uk}`)
    - traefik.http.middlewares.watchtower-https-redirect.redirectscheme.scheme=https
    - traefik.http.middlewares.sslheader.headers.customrequestheaders.X-Forwarded-Proto=https
    - traefik.http.routers.watchtower.middlewares=watchtower-https-redirect,sslheader
    - traefik.http.routers.watchtower-secure.entrypoints=https
    - traefik.http.routers.watchtower-secure.rule=Host(`watchtower.${domain_name:-dev.ac93.uk}`)
    - traefik.http.routers.watchtower-secure.tls=true
    - traefik.http.routers.watchtower.service=watchtower
    - traefik.http.services.watchtower.loadbalancer.server.port=8080
```

There are a couple of steps required if you're hosting in a private github repository and on github container registry.

Create a new personal access token [here](https://github.com/settings/tokens/new) with `read:packages` permission to pull down the image you will build in your CI & CD pipeline.

Use this new PAT to login to registry:

```bash
docker login ghcr.io -u alistaircol
```

The token will be added to `~/.docker/config.json`:

```json
{
	"auths": {
		"ghcr.io": {
			"auth": "redacted"
		}
	}
}
```

By default it's not the most [recommended](https://docs.docker.com/engine/reference/commandline/login/#credentials-store) solution, instead you should look to using an external credential store. If you're using a shared environment you may wish to look into a credential store.

The host `docker` config location defined as `docker_config_location` in `.env` is mounted into `watchtower` so it can authenticate with the registry to check for updates and pull.

## CI & CD Workflow

Probably the part you have been waiting for.

This is included in `bnss-app` repository, whereas everything else mentioned is in the `bnss` repository.

`.github/workflows/build-image.yaml`:

```yaml
---
name: Build application image
on:
  push:
    branches:
    - main
  pull_request:
    branches:
    - main
```

```yaml
env:
  IMAGE_NAME: bnss_members
  WATCHTOWER_HTTP_API_TOKEN: ${{ secrets.WATCHTOWER_HTTP_API_TOKEN }}
  WATCHTOWER_HTTP_API_URL: ${{ secrets.WATCHTOWER_HTTP_API_URL }}
```

```yaml
jobs:
  build:
    name: Build and deploy application
    runs-on: ubuntu-20.04
    permissions:
      packages: write
      contents: read
    env:
      working-directory: ./src

    steps:
```

```yaml
    - name: Login to ghcr.io registry
      run: |
        echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
```

```yaml
    - name: Setup repository
      uses: actions/checkout@v2
```

```yaml
    - name: Setup node
      uses: actions/setup-node@v2
      with:
        node-version: 16
        cache: npm
        cache-dependency-path: src/package-lock.json
```

```yaml
    - name: Install npm dependencies
      working-directory: ${{ env.working-directory }}
      run: |
        npm ci
```

```yaml
    - name: Build assets
      working-directory: ${{ env.working-directory }}
      run: |
        npm run prod
```

```yaml
    - name: Cache composer dev dependencies
      id: composer-cache-with-dev-dependencies
      uses: actions/cache@v2
      with:
        path: ${{ env.working-directory }}/vendor
        key: ${{ runner.os }}-composer-dev-${{ hashFiles('src/composer.lock') }}
        restore-keys: |
          ${{ runner.os }}-composer-dev-
```

```yaml
    - name: Check composer file
      working-directory: ${{ env.working-directory }}
      run: |
        composer validate --strict
```

```yaml
    - name: Install composer dependencies
      working-directory: ${{ env.working-directory }}
      run: |
        composer install --prefer-dist
```

```yaml
    - name: Run PHP linter
      working-directory: ${{ env.working-directory }}
      run: |
        composer run lint
```

```yaml
    - name: Run PHP code sniffer
      working-directory: ${{ env.working-directory }}
      run: |
        composer run style
```

```yaml
    - name: Cache composer dev dependencies
      id: composer-cache-without-dev-dependencies
      uses: actions/cache@v2
      with:
        path: ${{ env.working-directory }}/vendor
        key: ${{ runner.os }}-composer-without-dev-${{ hashFiles('src/composer.lock') }}
        restore-keys: |
          ${{ runner.os }}-composer-without-dev-
```

```yaml
    - name: Remove composer developer dependencies before building image
      working-directory: ${{ env.working-directory }}
      run: |
        composer install --no-dev
```

```yaml
    - name: Build image
      run: |
        make image
```

```yaml
    - name: Push image
      run: |
        IMAGE_ID=ghcr.io/${{ github.repository_owner }}/$IMAGE_NAME
        # Change all uppercase to lowercase
        IMAGE_ID=$(echo $IMAGE_ID | tr '[A-Z]' '[a-z]')
        # Strip git ref prefix from version
        VERSION=$(echo "${{ github.ref }}" | sed -e 's,.*/\(.*\),\1,')
        # Strip "v" prefix from tag name
        [[ "${{ github.ref }}" == "refs/tags/"* ]] && VERSION=$(echo $VERSION | sed -e 's/^v//')
        # Use Docker `latest` tag convention
        [ "$VERSION" == "master" ] && VERSION=latest
        echo IMAGE_ID=$IMAGE_ID
        echo VERSION=$VERSION
        docker tag $IMAGE_NAME $IMAGE_ID:$VERSION
        docker push $IMAGE_ID:$VERSION
```

```yaml
    - name: Notify watchtower
      run: |
        make watchtower
```

Most steps are self-explanatory and it's not the most complicated app so only basic sanity checks are performed.

The `Push image` step is taken from [example](https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions#upgrading-a-workflow-that-accesses-ghcrio) workflows.

## `make image`

Fairly simple. Using [`docker/buildx`](https://github.com/docker/buildx) action might be better.

`Makefile`:

```makefile
ifndef IMAGE_NAME
override IMAGE_NAME = bnss_members
endif

image:
	@docker build --file Dockerfile --tag $(IMAGE_NAME) .
```

### `Dockerfile`

The base image is the great [`webdevops/php-apache`](https://dockerfile.readthedocs.io/en/latest/content/DockerImages/dockerfiles/php-apache.html). This includes the web server obviously, but also `cron` so we can easily leverage `php artisan schedule:work` and `supervisor` for `php artisan queue:work`.

Thankfully `Dockerfile` for the application is relatively simple too.

The entire Laravel application is in the `src/` folder in this repo, so root of this repository has:

* `Makefile`
* `Dockerfile`
* `README.md`
* etc.

`Dockerfile`:

```dockerfile
FROM webdevops/php-apache:8.0
# These labels appear in the packages detail page on github
LABEL org.opencontainers.image.title=Example
LABEL org.opencontainers.image.description='Example'
LABEL org.opencontainers.image.vendor=alistaircol
LABEL org.opencontainers.image.url=https://dev.ac93.uk
LABEL org.opencontainers.image.source=https://github.com/alistaircol/bnss-app
WORKDIR /app
ENV WEB_DOCUMENT_ROOT=/app/public
ARG USER=application
ARG GROUP=www-data
COPY src/ /app
RUN chmod -R 777 /app/storage; \
    chmod -R 777 /app/bootstrap

COPY .docker/cron /etc/cron.d
COPY .docker/supervisor /opt/docker/etc/supervisor.d
COPY .docker/.bash_aliases /root/.bash_aliases
```

### `cron`

I have a couple of crons added to the image for:

* running [scheduled tasks](https://laravel.com/docs/8.x/scheduling), i.e. `php artisan schedule:work`
* running `php artisan migrate`

You can schedule things in Laravel in `app/Console/Kernel.php`'s `schedule` function, e.g.

```php
// run `php artisan something` at 1300 daily
$schedule->command('something')->dailyAt('13:00');
```

`.docker/cron/scheduler`:

```text
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |

* * * * * root php -f /app/artisan schedule:run
```

---

I will run `php artisan migrate` on `@reboot` since it will likely be rebooted when watchtower detects a change, and one of the changes may be a database change.

`.docker/cron/post-deploy`

```text
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |

@reboot root php -f /app/artisan migrate --force --step
```

### `supervisor`

I will add a `supervisor` config file to process queued jobs.

This is taken with minor modifications from Laravel [docs](https://laravel.com/docs/8.x/queues#configuring-supervisor) on queues.

I have opted to use database queues while I was testing for easy visibility.

`.docker/supervisor/queue-worker.conf`:

```ini
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php -f /app/artisan queue:work --sleep=3 --tries=3 --max-time=3600 database
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=application
numprocs=2
stopwaitsecs=3600
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

Note: for local development this isn't ideal if you are working on testing queued handlers, as the code changes won't be detected until the container has restarted. You might elect to maybe use `pm2` watching a certain directory and running a tailored `php artisan queue:work` command with `docker exec`, e.g.:

Haven't tested this but I'm sure you can figure it out.

`ecosystem.config.js`:

```js
// mpm install -g pm2
// pm2 start ecosystem.config.js

module.exports = {
  apps: [
    {
      name: "queue worker",
      cwd: "/absolute/path/to/app",
      script: "docker exec -t container_name bash -c 'php artisan queue:work database'",
      watch: true,
      autorestart: true,
    }
  ]
}
```

## `make watchtower`

The last step `make watchtower`, it just `HEAD`s an endpoint with bearer auth token.

`Makefile`:

```makefile
ifndef WATCHTOWER_HTTP_API_TOKEN
WATCHTOWER_HTTP_API_TOKEN = 01234567890ABCDEF
endif

ifndef WATCHTOWER_HTTP_API_URL
WATCHTOWER_HTTP_API_URL = http://localhost/v1/update
endif

watchtower:
	@$(info $(YELLOW)If you are running this you need to give WATCHTOWER_HTTP_API_TOKEN and WATCHTOWER_HTTP_API_URL - defaults are set$(RESET))
	@curl -I -H "Authorization: Bearer $(WATCHTOWER_HTTP_API_TOKEN)" $(WATCHTOWER_HTTP_API_URL)
```

![mongo-express](/img/articles/laravel-ci-cd/workflow.png)
