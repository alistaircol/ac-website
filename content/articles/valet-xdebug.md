---
title: "Using Xdebug with Laravel Valet"
author: "Ally"
summary: "Installing and configuring Xdebug with Laravel Valet."
publishDate: 2021-03-02T12:00:00+01:00
tags: ['xdebug', 'valet']
draft: false
---

First, assuming you have installed [`valet`](https://laravel.com/docs/8.x/valet):

```bash
pecl install xdebug
```

Next, find which files are loaded by the PHP installation:

```bash
php --ini
```

```text {hl_lines=[4]}
$ php --ini
Configuration File (php.ini) Path: /usr/local/etc/php/7.4
Loaded Configuration File:         /usr/local/etc/php/7.4/php.ini
Scan for additional .ini files in: /usr/local/etc/php/7.4/conf.d
/usr/local/etc/php/7.4/conf.d/error_log.ini,
/usr/local/etc/php/7.4/conf.d/ext-opcache.ini,
/usr/local/etc/php/7.4/conf.d/php-memory-limits.ini
```

Create a new file `99-xdebug.ini` in the `Scan for additional.ini files in` folder, i.e. `/usr/local/etc/php/7.4/conf.d`:

```ini
xdebug.mode = "develop,debug"
xdebug.client_host = "localhost"
xdebug.client_port = "9003"
xdebug.idekey = "phpstorm"
xdebug.start_with_request = "yes"
```

Then restart valet, `valet restart`.

---

I've added this to my `.zshrc` and effortless changes without having to remember the path and to reset valet for the config changes to be reloaded.

```bash
function xdebug
{
    nano /usr/local/etc/php/7.4/conf.d/99-xdebug.ini; valet restart
}
```

## Configuring PHPStorm

Go to preferences -> PHP.

I like to uncheck the two Force break.. checkboxes and set the Debug port to 9003 only (since I have port 9000 in use already for Graylog).

![PHPStorm: PHP preferences](/img/articles/valet-xdebug3/preferences-php.png)

Go to Run -> Edit configurations.

![PHPStorm: Empty configurations](/img/articles/valet-xdebug3/run-configurations-empty.png)

Attach new remote PHP.

<center>

![PHPStorm: Add configuration](/img/articles/valet-xdebug3/new-configuration.png)

</center>

Give a suitable name and IDE key.

![PHPStorm: Added configuration](/img/articles/valet-xdebug3/run-configurations-complete.png)
