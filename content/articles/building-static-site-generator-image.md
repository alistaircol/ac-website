---
title: "Building an image for static site generator output"
author: "Ally"
summary: "Bundling the generated output from a static site generator (e.g. `hugo`) into a simple static file server (e.g. `caddy`) for testing the build."
publishDate: 2021-07-12T21:01:31+0100
tags: ['hugo', 'docker', 'caddy']
draft: false
cover: https://ac93.uk/img/unsplash/victoire-joncheray-XsP7GCLMWjM-unsplash.jpg
---

I had a weird issue today with building my website.

It has a theme as a `gitmodule` but for some reason the remote pointed to the original repo, and not my forked version.

After much [frustration](https://stackoverflow.com/a/36593218/5873008), I eventually dropped the submodule and just included the theme with the main repo.

---

After doing this, there appeared to be no change and deployments were failing.

```text
8:47:58 PM: Error fetching branch: https://github.com/alistaircol/ac-netlify refs/heads/master
8:47:58 PM: Creating deploy upload records
8:47:58 PM: Failing build: Failed to prepare repo
8:47:58 PM: Failed during stage 'preparing repo': exit status 1
```

I prepared the following build script to emulate Netlify as best I can:

```shell
#!/usr/bin/env bash
# make a temporary directory to clone repo to
tmpdir=$(mktemp -d)

# listen for the following signals and tidy up the temporary directory
# 0: exit shell
# 2: Interrupt
# 3: Quit
# 15: Terminate
trap "rm -rf $tmpdir" 0 2 3 15

# clone repo to temporary directory
git clone git@github.com:alistaircol/ac-netlify.git $tmpdir

# build static site output
# using baseUrl is important
docker run \
  --rm \
  --tty \
  --interactive \
   --user=$(id -u) \
   --volume="$tmpdir:/src" \
   klakegg/hugo:0.75.1-ext \
   --baseUrl=http://localhost:9999

# put a simple Dockerfile to put static site output to caddy server
cat <<EOF > "$tmpdir/Dockerfile"
FROM caddy:2-alpine
WORKDIR /usr/share/caddy/
COPY ./public /usr/share/caddy/
EXPOSE 80
EOF

# copy static site output to simple web server
docker build --force-rm --tag=alistaircol/ac93 "$tmpdir"

# open browser (opens at error page initially)
open "http://localhost:9999"

# run the static site output server
docker run --rm -p 9999:80 alistaircol/ac93:latest
```

It turns out that on Netlify, it was pulling in cached data, so after clearing cache and re-deploying it worked!

![Netlify clear cache](/img/articles/static-site-build-docker-image/clear-netlify-cache.png)
