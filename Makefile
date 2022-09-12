PHONY: help

# https://gist.github.com/rsperl/d2dfe88a520968fbc1f49db0a29345b9
# define standard colors
BLACK        := $(shell tput -Txterm setaf 0)
RED          := $(shell tput -Txterm setaf 1)
GREEN        := $(shell tput -Txterm setaf 2)
YELLOW       := $(shell tput -Txterm setaf 3)
LIGHTPURPLE  := $(shell tput -Txterm setaf 4)
PURPLE       := $(shell tput -Txterm setaf 5)
BLUE         := $(shell tput -Txterm setaf 6)
WHITE        := $(shell tput -Txterm setaf 7)
RESET        := $(shell tput -Txterm sgr0)

image_name = klakegg/hugo:0.101.0-ext
lint_image_name = cytopia/yamllint:latest

docker_run = docker run \
	--rm \
	--interactive \
	--tty \
	--user=$(shell id -u):$(shell id -g) \
	--mount type=bind,source=$(shell pwd),target=/src \
	--workdir="/src"

tailwind = npx tailwindcss \
	--input="$(shell pwd)/resources/main.css" \
	--output="$(shell pwd)/static/css/main.css"

help:
	@echo 'Usage: make [${BLUE}subcommand${RESET}]'
	@echo 'subcommands:'
	@echo '  ${GREEN}server${RESET}    Mounts current ${WHITE}pwd${RESET} and runs ${WHITE}hugo server${RESET} in a ${WHITE}${image_name}${RESET} image'
	@echo '  ${GREEN}shell${RESET}     Mounts current ${WHITE}pwd${RESET} and runs ${WHITE}sh${RESET} in a ${WHITE}${image_name}${RESET} image'
	@echo '  ${GREEN}build${RESET}     Mounts current ${WHITE}pwd${RESET} and runs ${WHITE}hugo build${RESET} in a ${WHITE}${image_name}${RESET} image'
	@echo '  ${GREEN}article${RESET}   Mounts current ${WHITE}pwd${RESET} and runs a script to interactively create a new ${WHITE}md${RESET} file in ${WHITE}content/${RESET}'
	@echo '  ${GREEN}theme${RESET}     Runs ${WHITE}npx tailwind --watch${RESET}'
	@echo '  ${GREEN}assets${RESET}    Runs ${WHITE}npx tailwind --minify${RESET}'
	@echo '  ${GREEN}lint${RESET}      Mounts current ${WHITE}pwd${RESET} and runs ${WHITE}yamllint${RESET} in a ${WHITE}${lint_image_name}${RESET} image'

lint:
	@docker run --rm $(shell tty -s && echo "-it" || echo) -v "$(shell pwd):/data" ${lint_image_name} .

server:
	${docker_run} \
		--publish="1313:1313" \
		${image_name} server \
		--appendPort \
		--port 1313 \
		--noHTTPCache \
		--baseURL=http://localhost \
		--buildFuture \
		--buildDrafts

shell:
	${docker_run} --entrypoint="sh" ${image_name}

build:
	${docker_run} ${image_name}

article:
	@./.scripts/new-article

theme:
	@rm $(shell pwd)/static/css/main.css || exit 0
	@${tailwind} --watch

assets:
	@rm $(shell pwd)/static/css/main.css || exit 0
	@${tailwind} --minify

image:
	${docker_run} ${image_name} --baseUrl=http://localhost:9999
	docker build --force-rm --tag=alistaircol/ac93 .
	docker run --rm -p 9999:80 alistaircol/ac93:latest
