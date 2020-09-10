---
title: "Github Actions: Build code-generated assets, create a release and attach those assets to the release"
author: "Ally"
summary: "Automatically have Github Actions build some code-generated (binary) assets and attach to a release when a new tag is pushed."
publishDate: 2020-09-08T12:00:00+01:00
tags: ['github', 'git', 'php', 'tcpdf', 'ci']
draft: false
---

I have some code to generate a binary file (pdf). Generating locally is fine, but that might be on another computer, which requires effort to retrieve.

So I will use some Github CI to build for me!

The code is not important to this article, but basically it's a `php` script with some `composer` dependencies, mostly `tcpdf` which builds a file `output.pdf` into the repository root.

---

## Local Builds

Can build locally, using `docker` of course, something like this.

`Makefile`:

```make
build:
    docker run --rm --tty --user=$$(id -u) \
        --volume="$$(pwd):/app" \
        composer:latest \
        composer install
	
    docker run --rm --tty --user=$$(id -u) \
        --volume="$$(pwd):/app" \
        --workdir=/app \
        --env-file=".env" \
        php:7.4-cli \
        php src/index.php

open:
    xdg-open "output.pdf"
```

Have a `.env` file which is passed into `docker run` - values should not be quoted though, e.g.:

```text
NAME=Alistair Collins
ADDRESS=1 Random Street, Town, AA1 1AA
PHONE_OR_EMAIL=+44 07123 456 789 | email@website.com
WEBSITE=https://ac93.uk
```

## Github Builds

![build](/img/articles/github-pdf/build.png)

Main thing here is the absence of `.env` file. Instead, this is handled using Github secrets. Go to `Settings -> Secrets`, see `.env.example` for which ones you need to add.

![secrets](/img/articles/github-pdf/secrets.png)

---

The file described here is `.github/workflows/build.yml`.

```yml {linenos=true}
name: 'Build & Release'

on:
  push:
    tags:
      - 'v*'
```

Fairly self-explanatory, the jobs below are run when a tag starting with `v` is pushed. Read more on [`on`](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#on).

---

[`jobs`](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#jobs) - important lines are highlighed and some more information given below.

```yml {linenos=true, linenostart=7, hl_lines=[14 16 17 18 19 27 46 47 48]}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v2

      - name: Get Composer Cache Directory
        id: composer-cache
        run: |
          echo "::set-output name=dir::$(composer config cache-files-dir)"

      - name: 'Setup PHP'
        uses: shivammathur/setup-php@v2
        env:
          NAME: ${{ secrets.NAME }}
          ADDRESS: ${{ secrets.ADDRESS }}
          PHONE_OR_EMAIL: ${{ secrets.PHONE_OR_EMAIL }}
          WEBSITE: ${{ secrets.WEBSITE }}

      - name: 'Composer'
        run: |
          composer install

      - name: 'Build'
        run: |
          php src/index.php

      - name: 'Create Release'
        id: create_release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: ${{ github.ref }}
          draft: false
          prerelease: false

      - name: 'Upload Release Asset'
        id: upload-release-asset
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }} # This pulls from the CREATE RELEASE step above, referencing it's ID to get its outputs object, which include a `upload_url`. See this blog post for more info: https://jasonet.co/posts/new-features-of-github-actions/#passing-data-to-future-steps
          asset_path: ./output.pdf
          asset_name: cv.pdf
          asset_content_type: application/pdf

```

Entire file [here](https://gist.github.com/alistaircol/bc5fcc9f0cbd82c90387f338a8000c1d).

---

[`shivammathur/setup-php@v2`](https://github.com/shivammathur/setup-php#readme) is fairly configurable and comes with `composer`.

We are setting `env`s in this step too, this is so that our code has access to our repository secrets (our code basically takes `NAME`, etc. from `$_ENV` and prints into the pdf).

Line 33 `php src/index.php` - running this will create the `output.pdf` which should be attached to the release (see line 53).

Line 54 gives the name of the `output.pdf` on the release.

![release](/img/articles/github-pdf/release.png)


To push changes and trigger builds:

```bash
# make changes
git add ...
git commit -m '...'
git push origin master

git tag v0.0.2 -m 'updated current position'
git push origin v0.0.2
```

The last step will trigger the build and release.
