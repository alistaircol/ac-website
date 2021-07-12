---
title: "Open a Laravel website to LAN when using Laravel Valet"
author: "Ally"
summary: "Need to open Laravel website to your LAN when you're using Laravel Valet?"
publishDate: 2021-07-01T14:10:46+0100
tags: ['laravel', 'valet', 'nginx']
draft: true
---

Laravel documentation [has](https://laravel.com/docs/7.x/valet#sharing-sites) it pretty much said.

> Valet restricts incoming traffic to the internal 127.0.0.1 interface by default

> edit the appropriate Nginx configuration ... to remove the restriction on the listen directive by removing the 127.0.0.1: prefix on the directive for ports 80 and 443.

```bash
valet restart
```

> You cannot visit [website] at the moment because the website sent scrambled credentials that Google Chrome cannot process. Network errors and attacks are usually temporary, so this page will probably work later.
