PHONY: serve

image_name = klakegg/hugo:0.95.0-ext
docker_run = docker run --rm --interactive --tty --user=$(shell id -u) --volume="$(shell pwd):/src" --workdir="/src"
tailwind = npx tailwindcss \
	--input="$(shell pwd)/resources/main.css" \
	--output="$(shell pwd)/static/css/main.css"

lint:
	@docker run --rm $(shell tty -s && echo "-it" || echo) -v "$(shell pwd):/data" cytopia/yamllint:latest .

serve:
	${docker_run} --publish="1313:1313" ${image_name} server --buildDrafts --enableGitInfo --disableFastRender

build:
	${docker_run} ${image_name}

article:
	@./.scripts/new-article

theme:
	@rm $(pwd)/static/css/main.css || exit 0
	@${tailwind} --watch

assets:
	@rm $(pwd)/static/css/main.css || exit 0
	@${tailwind} --minify
