# My Website

Site built with `hugo` and a tailwind theme, based from the [papercss](https://themes.gohugo.io/theme/papercss-hugo-theme/) theme.

Everything below here needs reworked.

## Build/Develop

* `make server` runs `hugo server` in a container
* `make shell` runs `sh` in a container
* `make build` runs `hugo build` in a container
* `make article` runs an interactive script to create a new `.md` file in `content/`
* `make theme` runs `npx tailwindcss --watch` while creating changes to theme
* `make assets` runs `npx tailwind --minify` to commit changes to `static/`
* `make lint` runs `yamllint` in a container to verify syntax of `yaml` config files

---

Favicon generated with [favicon.io](https://favicon.io/favicon-generator/); foreground: `#ddddde`, background: `#2e2e33`, Roboto @ font size 90

## Blogging

Make a new article with `make article`.

Lint yaml files on commit, shouldn't edit many yaml files after initial setup.

```shell
git config core.hookspath "$(pwd)/.scripts"
```


## Development

I use Hugo inside a container `klakegg/hugo` Docker image.

Simply:

```
make
# or
make development
```

To start a development server.

```
$ make
docker run --rm --interactive --tty --user=$(id -u) --volume="$(pwd):/src" --publish="1313:1313" klakegg/hugo server

                   | EN  
-------------------+-----
  Pages            | 52  
  Paginator pages  |  0  
  Non-page files   |  0  
  Static files     | 95  
  Processed images |  0  
  Aliases          |  0  
  Sitemaps         |  1  
  Cleaned          |  0  

Built in 51 ms
Watching for changes in /src/{archetypes,content,layouts,static,themes}
Watching for config changes in /src/config.toml
Environment: "DEV"
Serving pages from memory
Running in Fast Render Mode. For full rebuilds on change: hugo server --disableFastRender
Web Server is available at http://localhost:1313/ (bind address 0.0.0.0)
Press Ctrl+C to stop
```
---

Alternatively:

```
make build
```

To build without launching a development server.

```
$ make build
docker run --rm --interactive --tty --user=$(id -u) --volume="$(pwd):/src" klakegg/hugo

                   | EN  
-------------------+-----
  Pages            | 52  
  Paginator pages  |  0  
  Non-page files   |  0  
  Static files     | 95  
  Processed images |  0  
  Aliases          |  0  
  Sitemaps         |  1  
  Cleaned          |  0  

Total in 58 ms
```

Sane WebStorm/PHP committing:

`Preferences > Version Control > Commit`

* Check `Use non-modal commit interface`
