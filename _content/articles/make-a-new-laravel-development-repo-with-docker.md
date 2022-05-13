---
title: "Creating a fresh Laravel installation with Docker"
author: "Ally"
summary: "A command I've used a few times to install a fresh Laravel project into the cwd's src/ folder, leaving the cwd for your own README, Docker, Terraform, etc. files"
publishDate: 2021-05-14T19:28:30+01:00
tags: ['laravel', 'docker', 'php', 'composer']
---

Why? Simply, because I like Docker to do these things, and because I have lots of urges to start a project but never complete it.

*But really, why?*

I like to leave the root directory for things, such as bespoke `README` for the entire project, and maybe other files, such as bash scripts, other infrastructure config, terraform scripts, etc. This has the bonus that it doesn't clutter up the Laravel 'workspace' and that `src` folder can have its own `README` for more bespoke details about the application itself rather than the entire project.

---

Just 3 easy steps:

- Make a new folder for your project, i.e. `mkdir -p development/my-new-saas-idea`
- `cd` into your new project folder, i.e. `cd development/my-new-saas-idea`
- Run the following command to install Laravel into `src/` in your project directory

```bash
docker run \
  --rm \
  --tty \
  --interactive \
  --user=$(id -u) \
  --volume="$(pwd):/app" \
  --volume="${COMPOSER_HOME:-$HOME/.composer}:/tmp" \
  composer:2.0 create-project laravel/laravel src
```

Could also add `--env COMPOSER_AUTH='{"github-oauth": {"github.com": ""}}'` if you require it.

This `composer` image comes with PHP 8 - if that's a problem, I've used `thecodingmachine/php:7.4-v3-cli` and friends in the past to accomplish the same thing.

---

Bonus aside: I finally got around to making a helper to make a blog post. 

![make article](/img/articles/make-article.png)

