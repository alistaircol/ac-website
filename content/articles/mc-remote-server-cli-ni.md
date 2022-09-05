---
title: "Connecting to a remote server with mc"
author: "Ally"
summary: "Connect to a remote server with mc from command line (non-interactive)."
publishDate: 2021-05-18T17:26:58+0100
tags: ['mc']
draft: false
---

I use [`mc`](https://midnight-commander.org/) to move/copy files on devices.

You can also use it to connect to a remote filesystem - more user-friendly than `scp`. I will connect from my laptop to my NAS.

## SSH Config

I will use `ssh` config for this. This will be in your `~/.ssh/config`:

```text
Host nas
  User ally
  HostName 192.168.1.2
  IdentityFile ~/.ssh/id_rsa
```

## `mc` with remote filesystem

To open up `mc` with your local filesystem and the remote filesystem (you can connect to two or change order):

```bash
mc . sh://[ssh host]
# i.e.
mc . sh://nas
# or
mc ~/Downloads sh://nas/path/on/nas
```

<center>

![mc](/img/articles/mc-remote/mc.png)

</center>
