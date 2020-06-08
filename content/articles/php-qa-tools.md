---
title: "Intergating Some PHP QA Tools"
author: "Ally"
summary: "How I integrated some PHP QA tools into my work process."
publishDate: 2020-06-07T12:00:00+01:00
tags: ['php', 'docker', 'bash', 'git', 'make']
draft: false
---

**TL;DR**:

* As the title says.
* Git repo [here](https://github.com/alistaircol/php-qa-tools-hook-integration).

---

We use the excellent bunch of PHP QA tools from the [`jakzal/phpqa`](https://hub.docker.com/r/jakzal/phpqa/) Docker image. 
We're only using a small subset of these tools for now, but decided to use the container option to save having to
install all these tools per project in `composer`.

To run some of these tools, we'll create a shortcut for them, in a `Makefile` per project.

Will create a `qa_docker` variable at the top of the `Makefile` to save typing this out for each QA check.
Used verbose `docker run` options for clarity.

`Makefile`:

```makefile
qa_docker = docker run \
    --init \
    --tty \
    --rm \
    --user=$$(id -u) \
    --volume="$$(pwd):/project" \
    --workdir "/project" \
    jakzal/phpqa:php7.3
```

## [`phplint`](https://github.com/overtrue/phplint/blob/master/README.md)

A fairly simple tool - it detects syntax (lint) errors in PHP code. Can be parallelised and gives context to your error(s).

Example: `.phplint.yml`:

```yml
path: ./
jobs: 10
cache: build/phplint.cache
extensions:
  - php
exclude:
  - vendor
```

The recipe for this one is easy! (the command is prefixed with `@` which stops the command being printed)

```makefile
phplint:
    @${qa_docker} phplint
```

Example (when everything is good):

```text
$ make phplint
phplint 2.0.2 by overtrue and contributors.

Loaded config from "/project/.phplint.yml"

.................................................

Time: < 1 sec	Memory: 12.0 MiB	Cache: Yes

OK! (Files: 1433, Success: 1433)
```

Example (when something isn't quite right):

```text
$ make phplint          
phplint 2.0.2 by overtrue and contributors.

Loaded config from "/project/.phplint.yml"

E

Time: < 1 sec	Memory: 12.0 MiB	Cache: Yes

FAILURES!
Files: 1433, Failures: 1

There was 1 errors:
1. /project/app/Model/Job.php:8611
    8608|         $updated = $this->updateAll(
    8609|             ['Job.void' => 0],
    8610|             ['Job.id' => $id]
  > 8611|         ));
    8612| 
    8613|         if (!$updated) {
    8614|             // redacted
 unexpected ')' in line 8611
```

It certainly beats my own implementation from years ago:

```bash
find app/ -type f \
    -regextype posix-egrep \
    -regex "app\/(Config|Console|Controller|Lib|Model|Test).*.php" \
    -exec php -l {} \; | (! grep -v "No syntax errors detected")
```

## [`phpcs`](https://github.com/squizlabs/PHP_CodeSniffer/blob/master/README.md)

Some of our code base is fairly old, so over time trying to polish it up (with `phpcbf`).

We're going to follow [PSR-12](https://www.php-fig.org/psr/psr-12/) (Mostly! base [`phpcs.xml`](https://github.com/squizlabs/PHP_CodeSniffer/blob/master/src/Standards/PSR12/ruleset.xml) for that).

`Makefile`:

```makefile
phpcs:
    @${qa_docker} phpcbs -s
```

The `-s` flag:

```text
 -s    Show sniff codes in all reports
```

Handy if your code is impossible to comply with *all* PSR-12 rules, you now know the code to add to an exemption list,
or tweak some rules parameters to suit.

Quick example on linting from `stdin`, but obviously can pass a path to a file, or a list (more on that later).

```bash
docker run -i jakzal/phpqa:php7.3 phpcs --standard=PSR12 -s - <<"PHP"
```
```php
<?php

echo "violation";

class Classy
{
    //
} 
```

```bash
PHP
```

You can see the output looks like this. Lines removed in diff are when run without `-s`.

```diff
 ----------------------------------------------------------------------
 FOUND 2 ERRORS AND 1 WARNING AFFECTING 3 LINES
 ----------------------------------------------------------------------
  1 | WARNING | [ ] A file should declare new symbols (classes,
    |         |     functions, constants, etc.) and cause no other
    |         |     side effects, or it should execute logic with side
    |         |     effects, but should not do both. The first symbol
    |         |     is defined on line 5 and the first side effect is
    |         |     on line 3.
-   |         |     (PSR1.Files.SideEffects.FoundWithSymbols)
  5 | ERROR   | [ ] Each class must be in a namespace of at least one
    |         |     level (a top-level vendor name)
-   |         |     (PSR1.Classes.ClassDeclaration.MissingNamespace)
  8 | ERROR   | [x] Whitespace found at end of line
-   |         |     (Squiz.WhiteSpace.SuperfluousWhitespace.EndLine)
 ----------------------------------------------------------------------
 PHPCBF CAN FIX THE 1 MARKED SNIFF VIOLATIONS AUTOMATICALLY
 ----------------------------------------------------------------------
```

## `phpcbf`

Uses the same config as `phpcs` but will try its best to fix these violations for you.

I haven't figured out how to integrate this into a workflow **yet**.

There is an easy access recipe.

`Makefile`:

```makefile
phpcbf:
    ${qa_docker} phpcbf $(args)
```

When I need to work in a file, I tend to follow this process:

* `make phpcbf args=src/Reader.php`
* `git commit -m '(phpcbf) Reader'`
* any additional tidy up (split long lines, replace magic numbers with `const` if applicable, other improvements, etc.) and `git commit`
* whatever I need to do and `git commit`

Some exceptions in our setup:

`phpcs.xml`:

```xml
    <!-- Kinnell Core Exceptions -->
    <rule ref="Generic.Arrays.DisallowLongArraySyntax"/>
    <rule ref="PSR1">
        <!-- Warning -->
        <!-- A file should declare new symbols (classes, functions, constants, etc.) -->
        <!-- and cause no other side effects, or it should execute logic with side -->
        <!-- effects, but should not do both. -->
        <!-- Rationale: We exclude this because Cake 2 isn't namespaced, -->
        <!-- so we need to use App::uses before class definitions -->
        <exclude name="PSR1.Files.SideEffects.FoundWithSymbols" />

        <!-- Error -->
        <!-- Each class must be in a namespace of at least one level -->
        <!-- (a top-level vendor name) -->
        <!-- Rationale: CakePHP 2.x models, etc. aren't namespaced -->
        <exclude name="PSR1.Classes.ClassDeclaration.MissingNamespace" />
    </rule>
    
    <!-- converts array() to [], etc. -->
    <rule ref="Generic.Arrays.DisallowLongArraySyntax.Found">
        <type>error</type>
    </rule>
```

## Violation Prevention (`git hooks`)

I'm pretty new to `git hooks` to prevent stuff from happening, though I've known about it for a long time.
I won't go into great detail about them, instead I suggest you watch this [tutorial](https://www.youtube.com/watch?v=fMYv6-SZsSo)
and refer to relevant git book [chapter](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks).
Each sample has a link to the content, the 
<i class="fa fa-info-circle"></i> will direct you to relevant section in `git hooks` `man` page for more info on them.

They usually live in `.git/hooks` so normally aren't part of a project in source control. 

- `.git/hooks`
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_applypatch_msg) [``applypatch-msg.sample``](https://github.com/git/git/blob/master/templates/hooks--applypatch-msg.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_commit_msg) [`commit-msg.sample`](https://github.com/git/git/blob/master/templates/hooks--commit-msg.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_fsmonitor_watchman) [`fsmonitor-watchman.sample`](https://github.com/git/git/blob/master/templates/hooks--fsmonitor-watchman.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#post-update) [`post-update.sample`](https://github.com/git/git/blob/master/templates/hooks--post-update.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_pre_applypatch) [`pre-applypatch.sample`](https://github.com/git/git/blob/master/templates/hooks--pre-applypatch.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_pre_commit) [`pre-commit.sample`](https://github.com/git/git/blob/master/templates/hooks--pre-commit.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_prepare_commit_msg) [`prepare-commit-msg.sample`](https://github.com/git/git/blob/master/templates/hooks--prepare-commit-msg.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_pre_push) [`pre-push.sample`](https://github.com/git/git/blob/master/templates/hooks--pre-push.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#_pre_rebase) [`pre-rebase.sample`](https://github.com/git/git/blob/master/templates/hooks--pre-rebase.sample)
- ├── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#pre-receive) [`pre-receive.sample`](https://github.com/git/git/blob/master/templates/hooks--pre-receive.sample)
- └── [<i class="fa fa-info-circle"></i>](https://git-scm.com/docs/githooks#update) [`update.sample`](https://github.com/git/git/blob/master/templates/hooks--update.sample)

Having the custom logic for your project *not* in source control is a bad idea, thankfully, however, there is
[`git config core.hookspath`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corehooksPath).

With this you can, for example, have a `.githooks` folder in your project with your custom hooks/logic and then tell `git` about it.

```bash
git config core.hookspath "$(pwd)/.githooks"
```

Now to get the hooks to work, give them the relevant name (i.e without `.sample` suffix) in `.githooks/` and make them
executable, i.e. `chmod +x`.

---

If we want to prevent a `git` action from happening, e.g. `git commit` when there are parse errors, then
we would likely want to add a `pre-commit` hook.

It might look something like this!

`.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Need to pass file to make since we're not in the same folder as it
ROOT_MAKE="make --file=$(git rev-parse --show-toplevel)/Makefile"
LINT_RESULT=$($ROOT_MAKE phplint)

if [ $? -eq "0" ]; then
  exit 0
else
  echo "There were some errors."
  echo "You must add these fixes before being allowed to commit."
  echo ""
  echo -e "$LINT_RESULT"
  exit 1
fi
```

Now this *probably* isn't really the logic you want to apply. We'll only want to lint files actually in the commit.
Think of the case if there's an error elsewhere in the local file system within the repository, but the change isn't
for something that's being committed, then this will be a false positive.

To get smarter results, add the following:

`Makefile`:

```makefile
files_in_git_diff = git \
    --no-pager \
    diff \
    --name-only \
    --staged

php_files_in_git_diff = ${files_in_git_diff} \
    --diff-filter=AMRC \
    -- '*.php'
```

Read more on:

* [`--name-only`](https://git-scm.com/docs/git-diff#Documentation/git-diff.txt---name-only)
* `--cached` it shows all staged changes. `--staged` is a synonym of `--cached`.
* [`--diff-filter`](https://git-scm.com/docs/git-diff#Documentation/git-diff.txt---diff-filterACDMRTUXB82308203).

Staging a file will then give something like below:

```text
$ make phpdiff
Reader.php
```

Now with a small tweak to the `phplint` recipe, we can make it more flexible.

We will allow `args` to be passed to `phplint`.

`Makefile`:

```diff
 phplint:
-       @${qa_docker} phplint
+       @${qa_docker} phplint $(args)
```

Example:

```text
$ make phplint args=--help
Description:
  Lint something

Usage:
  phplint [options] [--] [<path>...]

Arguments:
  path                               Path to file or directory to lint.

[truncated]
```

We can now combine `make phpdiff` with `make phplint` to lint only the relevant files to a commit.

Just another issue, `make phpdiff` will print one file per line, so we need to put them all on one line for `phpcs` args.

```diff
 phpcs:
-    @${qa_docker} phpcbs -s
+    @${qa_docker} phpcbs -s $(args)

+phpdiff-one-line:
+    @${php_files_in_git_diff} \
+        | paste --serial --delimiters=' '
```

Now to update the `pre-commit` hook to lint only relevant files. Might look something like this:

`.githooks/pre-commit`:

```diff
 #!/usr/bin/env bash
 ROOT_MAKE="make --file=$(git rev-parse --show-toplevel)/Makefile"
-LINT_RESULT=$($ROOT_MAKE phplint)
+LINT_RESULT=$($ROOT_MAKE phplint \
+    args=$($ROOT_MAKE phpdiff-one-line)
+)
```

A complete check might look something like this:

`.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
MAKE="make --file=$(git rev-parse --show-toplevel)/Makefile"
PHP_FILES_IN_DIFF=$($MAKE phpdiff)

if [ -z "$PHP_FILES_IN_DIFF" ]; then
  echo "# No PHP file changes detected. No phplint required."
  exit 0
fi

LINT_RESULT=$($MAKE phplint args="$(make phpdiff-one-line)")

if [ $? -eq "0" ]; then
  exit 0
else
  echo "There were some errors."
  echo "You must add these fixes before being allowed to commit."
  echo ""
  echo -e "$LINT_RESULT"
  exit 1
fi
```
