---
title: "Create a GitHub workflow to run PHP linters, tests, and generate coverage report"
summary: "Create and configure a GitHub workflow to run PHP QA tools (e.g. `phplint`, `phpcs`), and then run unit and feature tests (e.g. `php artisan test`, `phpunit`), and finally generate a code coverage report or some other artifact."
author: "Ally"
publishDate: 2022-09-05T17:40:52+0100
tags: ['laravel','github','phpunit']
cover: https://ac93.uk/img/articles/laravel-github-workflow-lint-run-unit-and-feature-tests-and-generate-code-coverage-report/workflow-summary.png
draft: false
---

## Overview

I will summarise how I set up a workflow, with some optimisations to:

* `lint`: run QA checks, and then
* `test`: run test suite in a Laravel app

In my scenario I run the following steps for each job:

* `lint`
  * [`overtrue/phplint`](https://github.com/overtrue/phplint): lints `php` files in parallel
  * [`squizlabs/php_codesniffer`](https://github.com/squizlabs/PHP_CodeSniffer): detects coding standard violations
* `test`:
  * `php artisan test`: run test suite
  * `XDEBUG_MODE=coverage composer exec phpunit`: generate code test coverage report

I will not go into detail on the configuration for `lint` steps, however for `test` there are some things I will mention regarding:

* `phpunit.xml`
* environment file
* migrations in `sqlite`

Unless mentioned otherwise, the `yaml` belongs in `.github/workflows/test.yaml`

TL;DR: [gist](https://gist.github.com/alistaircol/e636582d66b416c3ac5f76dcb21c82d6)

![Summary](/img/articles/laravel-github-workflow-lint-run-unit-and-feature-tests-and-generate-code-coverage-report/workflow-summary.png)

## Triggers

```yaml {linenos=true}
---
name: Pet Store
on:
  push:
    branches:
    - main
```

Self-explanatory, the workflow will run if commit(s) pushed to `main`.

You can also configure it to run on allow/deny list of branches/paths, and also `tag`s. See more info on `push` [here](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#push).

```yaml {linenos=true, linenostart=7}
  pull_request:
    branches:
    - main
```

The workflow will run if commit(s) pushed to a branch, for which there is an open PR, which has been configured to be merged into base branch `main`.

This can also be configured to run on certain paths like mentioned above in `push`. See [here](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request) for more info.

## Job to lint

This job will run first, it will do some QA checks, it is just basic linting and PSR code-sniffing for me, but you go as exotic as you feel.

```yaml {linenos=true, linenostart=11}
jobs:
  lint:
    runs-on: ubuntu-latest
```

## Optional: composer auth for pulling in a private package

In my project I am using a private package (an API SDK to be precise, you can read more about that [here](https://ac93.uk/articles/github-action-build-multiple-sets-of-documentation/)):

`composer.json`:

```json
{
    "name": "alistaircol/pet-store",
    "repositories": [
        {
            "type": "github",
            "url": "https://github.com/alistaircol/pet-store-api-sdk"
        }
    ],
    "require": {
        "alistaircol/pet-store-api-sdk": "*@dev"
    }
}
```

So it's required to add `COMPOSER_AUTH`, or `~/composer/auth.json` in the workflow runner.

```yaml {linenos=true, linenostart=14, hl_lines=[2,3]}
    env:
      COMPOSER_AUTH: >-
    {"github-oauth": { "github.com": ${{ secrets.PAT }} }}
```

You should create a Personal Access Token (PAT) with `repo` privileges. Learn how to [here](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token).

Otherwise you will get an error like the following:

```text
Failed to execute 

git clone --mirror -- \
    'git@github.com:alistaircol/pet-store-api-sdk.git' \
    '/home/runner/.cache/composer/vcs/git-github.com-alistaircol-pet-store-api-sdk.git/'

Cloning into bare repository '/home/runner/.cache/composer/vcs/git-github.com-alistaircol-pet-store-api-sdk.git'...
Warning: Permanently added the ECDSA host key for IP address 'REDACTED' to the list of known hosts.
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

## Job to lint... continued

```yaml {linenos=true, linenostart=17, hl_lines=[11,14,15,16,17]}
    steps:
    - name: Checkout
      uses: actions/checkout@v2
    - name: Setup PHP Action
      uses: shivammathur/setup-php@2.9.0
      with:
        php-version: 8.0
    - name: Validate composer.json and composer.lock
      run: composer validate
    - name: Cache Composer packages
      id: composer-cache
      uses: actions/cache@v2
      with:
        path: vendor
        key: ${{ runner.os }}-php-${{ hashFiles('**/composer.lock') }}
        restore-keys: |
     ${{ runner.os }}-php-
```

The last step in the above section (with `id` of `composer-cache`) will retrieve the `vendor` files for the `composer.lock` file from cache.

This is a slight optimisation on the time spent in the workflow by not downloading the files externally, but instead retrieving them from a cache.

Notes on [`actons/cache`](https://github.com/actions/cache):

* Line 27: it's required to set an `id` to access the step's `output` in a later step
* Line 30: the path to commit to cache
* Line 31: the key to restore and commit to cache
* Line 33: an ordered list of keys to use for restoring stale cache if no cache hit occurred for key

```yaml {linenos=true, linenostart=34, hl_lines=[2]}
    - name: Install dependencies
      if: steps.composer-cache.outputs.cache-hit != 'true'
      run: composer install --prefer-dist --no-progress --no-suggest
```

You can see the optimisation in force here. It will only run `composer install` when there is no cache-hit.

```yaml {linenos=true, linenostart=38, hl_lines=[6,7]}
    - name: Determine if linting is required
      id: linting-required
      uses: tj-actions/changed-files@v29.0.3
      with:
        files: |
          app/**/*.php
          config/**/*.php
```

You can see I am preparing for another optimisation with [`tj-actions/changed-files`](https://github.com/tj-actions/changed-files#outputs).

* `A`: Added
* `C`: Copied
* `M`: Modified
* `D`: Deleted
* `R`: Renamed

For this optimisation, I only want to run the next steps when any `php` file in `app` and `config` has been changed or modified (ACMR).

This optimisation is handy if you are building front-end task, working on documentation, or debugging workflows 😉 and have no need to run these, think of the CPU cycles saved!

```yaml {linenos=true, linenostart=45, hl_lines=[3,4,8,9]}
    - name: PHP Lint Check
      if: >-
        steps.linting-required.outputs.only_changed == 'true' 
        || steps.linting-required.outputs.only_modified == 'true'
      run: composer run lint
    - name: PSR2 Code Sniffer
      if: >-
        steps.linting-required.outputs.only_changed == 'true' 
        || steps.linting-required.outputs.only_modified == 'true'
      run: composer run style
```

![Lint](/img/articles/laravel-github-workflow-lint-run-unit-and-feature-tests-and-generate-code-coverage-report/workflow-lint.png)

## Job to test

The first few steps of this job are relatively similar to the linting job above.

```yaml {linenos=true, linenostart=56, hl_lines=[3]}
  test:
    runs-on: ubuntu-latest
    needs: lint
```

Having `needs` as `lint`, i.e. name of the first job, means that this job will only run if the `lint` job has been completed successfully.

There's no point running the test suite to check your code semantics if there is possibly syntactically incorrect code.

```yaml {linenos=true, linenostart=59}
    env:
      COMPOSER_AUTH: >-
    {"github-oauth": { "github.com": ${{ secrets.PAT }} }}
```

```yaml {linenos=true, linenostart=63, hl_lines=[8]}
    steps:
    - name: Checkout
      uses: actions/checkout@v2
    - name: Setup PHP Action
      uses: shivammathur/setup-php@2.9.0
      with:
        php-version: 8.0
        extensions: pdo_sqlite, sqlite3, xdebug
```

Here I explicitly set the extensions we need to run the test suite.

The next few steps will be similar to `lint`:

```yaml {linenos=true, linenostart=71, hl_lines=[11]}
    - name: Validate composer.json and composer.lock
      run: composer validate
    - name: Cache Composer packages
      id: composer-cache
      uses: actions/cache@v2
      with:
        path: vendor
        key: ${{ runner.os }}-php-${{ hashFiles('**/composer.lock') }}
        restore-keys: |
     ${{ runner.os }}-php-
    - name: Install dependencies
      if: steps.composer-cache.outputs.cache-hit != 'true'
      run: composer install --prefer-dist --no-progress --no-suggest
```

With the PHP runtime, and dependencies set-up, we are almost ready to run the test suite. A couple of things worth noting before running the test suite:

* Create an empty `sqlite` database in `database/database.sqlite` for the test suite.
* It's required to run migrations before starting tests which use [`RefreshDatabase`](https://laravel.com/docs/8.x/database-testing#resetting-the-database-after-each-test), so I do that.
* Use a very stripped down `.env.testing` and copy it to `.env`, i.e.:

```text
APP_NAME="Ally's Pet Store"
APP_ENV=testing
APP_KEY=base64:EURcoEN1DkuOyJvAMh6dzR3Y8YOI1M9WzMCUL6A7WfY=
APP_DEBUG=true
APP_URL=https://pet-store.ac93.uk

DB_CONNECTION=sqlite
```

## Optional: note on migrations

You might run into some issues when running an `alter table` query.

I was adding a new column to a table which was implicitly not nullable `nullable(false)`, but didn't have an explicit `default`.

This works just fine for `mysql`, and for me in `sqlite` it worked, however in `sqlite` in the github worker, it didn't!

I found a solution in this stackoverflow [thread](https://stackoverflow.com/questions/20822159/laravel-migration-with-sqlite-cannot-add-a-not-null-column-with-default-value-n):

`database/migrations/whatever.php`:

```php {linenos=true, hl_lines=[12,13,14,17,18]}
<?php

use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        $driver = Schema::connection($this->getConnection())
            ->getConnection()
            ->getDriverName();

        Schema::table('pets', function (Blueprint $table) use ($driver) {
            if ($driver === 'sqlite') {
                $table->uuid('uuid')->default('');
            } else {
                $table->uuid('uuid')->unique()->after('id');
            }
        });
    }

    public function down()
    {
        Schema::table('pets', function (Blueprint $table) {
            $table->dropColumn('uuid');
        });
    }
}
```

There is likely some more elegant solution, but this is good enough for me, for now.

## Job to test... continued

These commands will get the test suite ready:

```yaml {linenos=true, linenostart=84}
    - name: Run Preamble
      run: |
        mkdir -p database
        touch database/database.sqlite
        cp .env.testing .env
        rm .env.example
        php artisan migrate --database=sqlite
        mkdir -p build/coverage
```

We can now run the tests. I use  `php artisan test` with some `--filter=PetStore` in a `composer.json`'s `script` section.

i.e. `composer.json`:

```json
{
    "scripts": {
        "tests": [
            "@php artisan test --filter=PetStore"
        ]
    }
}
```

The filter means that it will only run tests in `tests/[Unit|Feature]/PetStore/**/*Test.php`.

```yaml {linenos=true, linenostart=92}
    - name: Run tests
      run: composer run tests
```

The `phpunit.xml` has a `coverage` section added:

```xml {hl_lines=[15,16,17,18,19,20,21,22]}
<?xml version="1.0" encoding="UTF-8"?>
<phpunit
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="./vendor/phpunit/phpunit/phpunit.xsd"
    bootstrap="vendor/autoload.php"
    colors="true">
    <testsuites>
        <testsuite name="Unit">
            <directory suffix="Test.php">./tests/Unit</directory>
        </testsuite>
        <testsuite name="Feature">
            <directory suffix="Test.php">./tests/Feature</directory>
        </testsuite>
    </testsuites>
    <coverage processUncoveredFiles="true">
        <include>
            <directory suffix=".php">./app/PetStore</directory>
        </include>
        <report>
            <html outputDirectory="build/coverage" />
        </report>
    </coverage>
    <php>
        <server name="APP_ENV" value="testing" />
        <server name="BCRYPT_ROUNDS" value="4" />
        <server name="CACHE_DRIVER" value="array" />
        <server name="MAIL_MAILER" value="array" />
        <server name="QUEUE_CONNECTION" value="sync" />
        <server name="SESSION_DRIVER" value="array" />
        <server name="TELESCOPE_ENABLED" value="false" />
    </php>
</phpunit>
```

The above highlighted lines are needed to generate a coverage report for the code in `app/PetStore` to `build/coverage`.

i.e. `composer.json`:

```json
{
    "scripts": {
        "coverage": [
            "rm -rf build/coverage || :",
            "XDEBUG_MODE=coverage composer exec phpunit"
        ]
    }
}
```

```yaml {linenos=true, linenostart=94}
    - name: Generate coverage report
      run: composer run coverage
```

Finally, I will create an artifact, which includes the code coverage output.

This essentially will `zip` everything in `build/coverage` and then it can from the workflow run page.

```yaml {linenos=true, linenostart=96}
    - name: Archive code coverage results
      uses: actions/upload-artifact@v3
      with:
        name: code-coverage-report
        path: build/coverage
```

You could possibly add a similar optimisation from `lint` to skip running tests if no `php` changes have been made.

![Test](/img/articles/laravel-github-workflow-lint-run-unit-and-feature-tests-and-generate-code-coverage-report/workflow-test.png)

## Gist

You can see gist [here](https://gist.github.com/alistaircol/e636582d66b416c3ac5f76dcb21c82d6) 

--- 

You may be interested in from my previous article(s) on:

* [Building and hosting a full CI & CD containerised Laravel application](https://ac93.uk/articles/building-and-hosting-a-full-ci-cd-containerised-laravel-application/).
