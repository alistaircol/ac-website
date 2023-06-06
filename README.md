# My Website

Site built with `hugo` and a tailwind theme, based from the [papercss](https://themes.gohugo.io/theme/papercss-hugo-theme/) theme but extensively modified.

Features:

* No explicit trackers, some JS loaded from CDN.
* RSS [feed](https://ac93.uk/articles/index.xml) for integration with [`my github workflow`](https://github.com/alistaircol/alistaircol/blob/master/.github/workflows/blog-post-workflow.yml) to update my [github profile](https://github.com/alistaircol).
* Asynchronous search with [`fuse`](https://fusejs.io/) and [`Alpine.js`](https://alpinejs.dev/).
* Comment integration with [`utteranc.es`](https://utteranc.es/).
* Some SEO, and good Lighthouse audit score.
* Hosted on Cloudflare Pages.
* Staging hosted on [netlify](https://ac-website.netlify.app/)

Mostly a tech blog for my own reference.

## Colors

| Function | Class | Color |
|----------|-------|-------|
| background | `ac-background` | `#1d1e20` | 
| text | `gray-400` | `#9ca3af` |
| link, titles | `white` | `#ffffff` |
| accent | `gray-800` | `#1f2937` |
| code | `sky-500` | `#0ba5e9` |

Favicon generated with [favicon.io](https://favicon.io/favicon-generator/); foreground: `#ddddde`, background: `#2e2e33`, font: `Roboto` @ size `90`.

## Build/Develop

Use `task` over `make`. `make` remains as netlify uses this.

* `task server` runs `hugo server` in a container
* `task shell` runs `sh` in a container
* `task build` runs `hugo build` in a container
* `task theme` runs `npx tailwindcss --watch` while creating changes to theme
* `task assets` runs `npx tailwind --minify` to commit changes to `static/`
* `task lint` runs `yamllint` in a container to verify syntax of `yaml` config files

### Node

* Install [`nvm`](https://github.com/nvm-sh/nvm#installing-and-updating)
* Install newest LTS `nvm install --lts`
* Use newest LTS `nvm use --lts`
* Install stuff `npm install`

### Misc

Lint yaml files on commit, shouldn't edit many yaml files after initial setup.

```shell
git config core.hookspath "$(pwd)/.scripts"
```

Sane WebStorm/PHP committing:

`Preferences > Version Control > Commit`

* Check `Use non-modal commit interface`
