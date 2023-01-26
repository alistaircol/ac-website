---
title: "Querying an IP restricted API with Postman"
author: "Ally"
summary: "Use a SOCKS proxy to query an IP restricted API with Postman."
publishDate: 2020-09-11T12:00:00+01:00
tags: ['proxy', 'socks', 'ssh', 'postman']
draft: false
cover: https://ac93.uk/img/unsplash/jakob-soby-RjPG-_LVmiQ-unsplash.jpg
---

Unfortunately Postman doesn't support SOCKS proxy, so have to find something else. No problem.

## Tunnel/SOCKS proxy

```bash
ssh -D 7777 -fCqN -I ~/.ssh/id_rsa my-host
```

* `-D`: The bind address.
* `-f`: Requests ssh to go to background just before command execution.
* `-C`: Requests compression of all data.
* `-q`: Quiet mode.
* `-N`: Do not execute a remote command. This is useful for just forwarding ports.
* `-I`:  Specify the PKCS#11 shared library ssh should use to communicate with a PKCS#11 token providing keys for user authentication.
* `~/ssh/id_rsa`: Public key to use
* `my-host`: Entry in `~/.ssh/config`'s `Host`

## HTTP to SOCKS proxy

Install:

```bash
npm install -g http-proxy-to-socks
```

Run the proxy:

```bash
hpts -s 127.0.0.1:7777 -p 7788
```

Set up Postman to use the HTTP proxy.

File → Settings → Proxy → Add a Custom Proxy Configuration

<center>

![postman](/img/articles/postman-proxy/postman-proxy.png)

</center>

Good luck.

---

<center>

![meme](/img/articles/postman-proxy/meme.jpg)

</center>
