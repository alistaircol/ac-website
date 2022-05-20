PHONY: serve

image_name = klakegg/hugo:0.95.0-ext
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

lint:
	@docker run --rm $(shell tty -s && echo "-it" || echo) -v "$(shell pwd):/data" cytopia/yamllint:latest .

serve:
	${docker_run} \
		--publish="1313:1313" \
		${image_name} server \
		--appendPort \
		--port 1313 \
		--noHTTPCache \
		--baseURL=http://localhost \
		--buildFuture

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
