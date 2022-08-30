---
title: "Setting up CI to build and release multiple sets of documentation for a project"
author: "Ally"
summary: "Learn how to set up GitHub action to build documentation (PHP, OpenAPI) from multiple generators and consolidate them all into a single `gh-pages` branch"
publishDate: 2022-08-26T18:06:53+0100
tags: ['github','php','openapi']
---

Recently I had to work on an integration with an external API from an OpenAPI spec.

I generate a sdk from this file, and push the resultant code to the repository where there is a workflow to build and release documentation from the spec, as well as the PHP SDK.

## OpenAPI Generator

Using the OpenAPI generator makes a ton of sense, instead of using something like Laravel's [`Http`](https://laravel.com/docs/9.x/http-client) client and transforming the response, etc. in a project. OpenAPI generator will just take a spec file and generate an entire SDK in seconds, it can create server/client in a range of languages and frameworks.

I will generate a PHP client, and obviously use `docker` to do it.

### Templates (optional)

I had to override some templates (mostly just `README.md` and `.gitignore`) and used the following command to publish them.

```bash
docker run \
    --rm \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd):/local" \
    --workdir=/local \
    openapitools/openapi-generator-cli \
    author template -g php -o .generator/templates
```

```text
[main] INFO  o.o.codegen.cmd.AuthorTemplate - Extracted templates to '.generator/templates' directory. Refer to https://openapi-generator.tech/docs/templating for customization details.
```

### Ignoring files (optional)

I also used the `.openapi-generator-ignore` to not publish files we don't need to reduce clutter (i.e. travis and cs fixer).

```gitignore
.php-cs-fixer.dist.php
.travis.yml
git_push.sh
phpunit.xml.dist
```

### Config

I use `yaml` file instead of command line arguments to:

* set namespace of the package, i.e. `Ally\PetStore`
* set directory of the models within the package, e.g. `Schema`, i.e. `Ally\PetStore\Schema`
* set the package git user, e.g. `alistaircol`
* set the package git repo, e.g. `pet-store-api-sdk`
* some other things

`spec/config.yaml`:

```yaml
---
globalProperties:
  apiDocs: false
  modelDocs: false
  apiTests: false
  modelTests: false

# The main namespace to use for all classes.
invokerPackage: Ally\PetStore
# model/dto package
modelPackage: Schema
# path to folder, probably will just be same as gitRepoId for consistency
packageName: pet-store-api-sdk
srcBasePath: src/
gitUserId: alistaircol
gitRepoId: pet-store-api-sdk

# for the html2 docs
phpInvokerPackage: Ally\PetStore
```

### Generating

Using this following command will generate the SDK. Once it's generated add, commit and push.

It will generate the code (obviously), as well as a `README` with instructions on how to use it in another project with `composer` and some documentation about the API endpoints, models and authorization.

```bash
docker run \
    --rm \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd):/local" \
    --workdir=/local \
    openapitools/openapi-generator-cli \
    generate \
    --template-dir=.generator/templates \
    --config=spec/config.yaml \
    --input-spec=spec/api.yaml \
    --generator-name=php \
    --output=.
```

## Documentation

I chose four documentation generators, each having their own advantages and disadvantages.

* [doctum](https://github.com/code-lts/doctum) is my favourite - nice UI with all classes, properties and method signature overviews, and search. It's what [Laravel](https://laravel.com/api/9.x/) uses.
* [doxygen](http://www.doxygen.org/index.html) requires more clicks than doctum to get the details you might want, but it includes actual source code in the documentation, includes class inheritance diagrams, and search. Has the most verbose config file.
* [openapi](https://openapi-generator.tech) the others mentioned look at the SDK code whereas this is generated from the spec directly - gives great overview of the spec file.
* [phpdoc(umentor)](https://www.phpdoc.org/) my least favourite - has similar but more modern UI compared to doxygen, but surfaces about the same information as doctum (i.e. without the code & inheritance from doxygen).

All the documentation output will go to `.generator/docs`.

## Doctum

[![Doctum](/img/articles/github-action-build-multiple-sets-of-documentation/doc_doctum.png)](https://alistaircol.github.io/pet-store-api-sdk/doctum/index.html)

### Config

I use the following config to build the documentation:

`doctum.php`:

```php
<?php

$options = [
    'dir' => __DIR__,
    'title' => 'Ally\'s PetStore API',
    'build_dir' => __DIR__ . '/.generator/docs/doctum',
    'cache_dir' => __DIR__ . '/.generator/cache/doctum',
    'default_opened_level' => 5,
];

return new Doctum\Doctum(__DIR__, $options);
```

### Build

I use the following command to build the documentation for `docutum`:

```bash
curl -o .generator/bin/doctum.phar https://doctum.long-term.support/releases/latest/doctum.phar
chmod +x .generator/bin/doctum.phar
php .generator/bin/doctum.phar parse --force --ignore-parse-errors doctum.php
php .generator/bin/doctum.phar render --force --ignore-parse-errors doctum.php
```

## Doxygen

[![Doxygen](/img/articles/github-action-build-multiple-sets-of-documentation/doc_doxygen.png)](https://alistaircol.github.io/pet-store-api-sdk/doxygen/index.html)

### Config

The config file is insane, I grabbed the [`Doxyfile`](https://github.com/doxygen/doxygen/blob/master/Doxyfile) and made the following (a non-exhaustive list) changes:

`Doxyfile`:

```text
INPUT            = src/
FILE_PATTERNS    = *.php \
                   *.md
RECURSIVE        = YES
PROJECT_NAME     = Ally's PetStore API
OUTPUT_DIRECTORY = .generator/docs/doxygen
GENERATE_LATEX   = NO
```

### Build

I use the following command to build the documentation for `doxygen`:

```bash
docker run \
    --rm \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd):/local" \
    --workdir=/local \
    greenbone/doxygen \
    doxygen Doxyfile
```

## OpenAPI

[![OpenAPI](/img/articles/github-action-build-multiple-sets-of-documentation/doc_openapi.png)](https://alistaircol.github.io/pet-store-api-sdk/openapi/index.html)

### Build

I use the following command to build the documentation for `openapi`:

```bash
docker run \
    --rm \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd):/local" \
    --workdir=/local \
    openapitools/openapi-generator-cli \
    generate \
  --template-dir=.generator/templates \
  --config=spec/config.yaml \
  --input-spec=spec/api.yaml \
  --generator-name=html2 \
  --output=.generator/docs/openapi
```

## PHPDoc

[![PHPDoc](/img/articles/github-action-build-multiple-sets-of-documentation/doc_phpdoc.png)](https://alistaircol.github.io/pet-store-api-sdk/phpdoc/index.html)

### Config

I use the following simple config for `phpdoc`:

`phpdoc.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<phpdocumentor
  configVersion="3"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="https://www.phpdoc.org"
  xsi:noNamespaceSchemaLocation="https://docs.phpdoc.org/latest/phpdoc.xsd">
  <title>Ally's PetStore API</title>
  <paths>
    <output>.generator/docs/phpdoc</output>
    <cache>.generator/cache/phpdoc</cache>
  </paths>


  <version number="latest">
    <api>
      <source dsn=".">
        <path>src</path>
      </source>
    </api>
  </version>
</phpdocumentor>

```

### Build

I use the following command to build the documentation for `phpdoc`:

```bash
docker run \
    --rm \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd):/local" \
    --workdir=/local \
    phpdoc/phpdoc:3 \
    --config=phpdoc.xml run
```

## Taskfile

For all the documentation generators mentioned above, I have added them to a `taskfile.yaml` and I use this in the workflow.

It will look something like this:

`taskfile.yaml`:

```yaml
---
# yaml things: https://stackoverflow.com/a/22483116/5873008
version: 3
tasks:
  # i.e. code
  default:
    cmds:
    - >-
```
```bash
      docker run \
        --rm \
        --user=$(id -u):$(id -g) \
        --volume="$(pwd):/local" \
        --workdir=/local \
        openapitools/openapi-generator-cli \
        generate \
        --template-dir=.generator/templates \
        --config=spec/config.yaml \
        --input-spec=spec/api.yaml \
        --generator-name=php \
        --output=.
```

```yaml
    interactive: true

  docs:
    cmds:
    - task: doctum
    - task: doxygen
    - task: openapi
    - task: phpdoc

  doctum:
    cmds:
    - mkdir -p .generator/bin
    - curl -o .generator/bin/doctum.phar https://doctum.long-term.support/releases/latest/doctum.phar
    - chmod +x .generator/bin/doctum.phar
    - php .generator/bin/doctum.phar parse --force --ignore-parse-errors doctum.php
    - php .generator/bin/doctum.phar render --force --ignore-parse-errors doctum.php
    interactive: true

  doxygen:
    cmds:
    - >-
```

```bash
      docker run \
        --rm \
        --user=$(id -u):$(id -g) \
        --volume="$(pwd):/local" \
        --workdir=/local \
        greenbone/doxygen \
        doxygen Doxyfile
```

```yaml
    interactive: true

  openapi:
    cmds:
    - >-
```

```bash
      docker run \
        --rm \
        --user=$(id -u):$(id -g) \
        --volume="$(pwd):/local" \
        --workdir=/local \
        openapitools/openapi-generator-cli \
        generate \
        --template-dir=.generator/templates \
        --config=spec/config.yaml \
        --input-spec=spec/api.yaml \
        --generator-name=html2 \
        --output=.generator/docs/openapi
```

```yaml
    interactive: true

  phpdoc:
    cmds:
    - >-
```

```bash
      docker run \
        --rm \
        --user=$(id -u):$(id -g) \
        --volume="$(pwd):/local" \
        --workdir=/local \
        phpdoc/phpdoc:3 \
        --config=phpdoc.xml run
```

```yaml
    interactive: true
```

[`task`](https://taskfile.dev/) is infinitely better than `make` in my opinion, since it supports variables and other features in a much nicer way. It's just yaml!

Generating things locally:

* code: `task`
* docs: `task docs`

Easy! 😍

## GitHub Workflow

![Workflow](/img/articles/github-action-build-multiple-sets-of-documentation/workflow.png)

For the workflow I will use a `matrix` `strategy` to invoke `task {matrix}` to generate the documentation.

```yaml
---
name: Build application documentation
on:
  workflow_dispatch:

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    strategy:
      matrix:
        affix:
        - doctum
        - doxygen
        - openapi
        - phpdoc
```

It is currently just set up to run manually, but you can specify on tag, branch, PR, etc.

```yaml
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    - name: Install Task
      uses: arduino/setup-task@v1
    - name: Install PHP
      uses: shivammathur/setup-php@2.9.0
      with:
        php-version: 7.4
      if: >-
        ${{ matrix.affix }} == 'doctum'
```

```yaml
    - name: Create `${{ matrix.affix }}` documentation
      id: documentation_context
      run: task --taskfile=taskfile.yaml ${{ matrix.affix }}
    - name: Release `${{ matrix.affix }}` documentation
      uses: JamesIves/github-pages-deploy-action@v4
      with:
        token: ${{ secrets.GITHUB_TOKEN }}
        branch: gh-pages-${{ matrix.affix }}
        folder: ${{ steps.documentation_context.outputs.directory }}
        clean: true
```

This will create a branch for each of the documentation generators. These can be cloned and checked out to the branch if desired.

Another job to consolidate the branches into a single branch:

```yaml
  release:
    permissions:
      contents: write
    name: Release
    runs-on: ubuntu-latest
    needs: build
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    - name: Checkout doctum
      uses: actions/checkout@v3
      with:
        ref: gh-pages-doctum
        path: release/doctum
    - name: Checkout doxygen
      uses: actions/checkout@v3
      with:
        ref: gh-pages-doxygen
        path: release/doxygen
    - name: Checkout openapi
      uses: actions/checkout@v3
      with:
        ref: gh-pages-openapi
        path: release/openapi
    - name: Checkout phpdoc
      uses: actions/checkout@v3
      with:
        ref: gh-pages-phpdoc
        path: release/phpdoc
    - name: Go to root
      run: |
        cd "$GITHUB_WORKSPACE"
```

This last step might seem strange, but it is required.

```text
There was an error initializing the repository:
    The process '/usr/bin/git' failed with exit code 128 ❌
Notice: Deployment failed!
```

There might be a nicer solution (it's not too bad after all) to this problem.

The last step will consolidate all the documentation we have just checked out into another separate branch.

```yaml
    - name: Release documentation bundle
      uses: JamesIves/github-pages-deploy-action@v4
      with:
        branch: gh-pages
        folder: release
        clean: false
```

I add a custom landing page (`index.html`) into the consolidated `gh-pages` branch. Afterwards you should have no need to touch it again.

![Branches](/img/articles/github-action-build-multiple-sets-of-documentation/branches.png)

## GitHub Pages

Go to the repository's settings, then go to pages under code and automation and configure.

* Source: deploy from a branch
* Branch: `gh-pages` and `/ (root)`

![Pages](/img/articles/github-action-build-multiple-sets-of-documentation/pages.png)

After a few minutes the consolidated set of documentation will be available.

**Note**: if you have a `{username}.github.io` repository with a `CNAME` file it may cause some issues.

This will add a new workflow, which will be run when changes are pushed to `gh-pages` branch.

![Pages Workflow](/img/articles/github-action-build-multiple-sets-of-documentation/pages-workflow.png)

You can see the consolidated documentation [here](https://alistaircol.github.io/pet-store-api-sdk) and the repo example [here](https://github.com/alistaircol/pet-store-api-sdk).
