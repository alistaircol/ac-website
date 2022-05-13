---
title: "A nicer, more efficient terminal experience with tmux and tmuxinator."
author: "Ally"
summary: "Friendship ended with `terminator`, now `tmux` is my best friend."
publishDate: 2020-06-09T12:00:00+01:00
tags: ['tmux']
draft: false
---

![tmuxinator screenshot](/img/articles/tmuxinator/tmux-screenshot.png)

> Screenshot from Iterm 2 using [JetBrains Mono Regular](https://www.jetbrains.com/lp/mono/) font.

I used [terminator](https://terminator-gtk3.readthedocs.io/en/latest/) for the longest time when developing, the main
appeal was the ability to split terminals. I would work on many sites (distinct git repositories) - one per tab, and
within the tab it'd be split horizontally, top being host machine and bottom being inside the docker container at the
same location (i.e. project root). This was configurable, but it was kinda nasty.

Ultimately decided to jump to tmux, because moving the mouse is difficult! I haven't looked back since.

To follow this tutorial, you should install the following:

* [`tmuxinator`](https://github.com/tmuxinator/tmuxinator) - load tmux session from a config file.
* [`tpm`](https://github.com/tmux-plugins/tpm) - plugins and themes.

The [tmux cheatsheet](https://tmuxcheatsheet.com/) is a great introduction.

---

My tmux config file is pretty simple, change a couple bindings and load some plugins.

`~/.tmux.conf`:

```text
# https://superuser.com/a/388243
# set default shell as zsh 
# didn't need in plain ubuntu, but required for my regolith instal
# set-option -g default-shell /bin/zsh

# CTRL + A for prefix
set-option -g prefix ^a

# switch panes using Alt-arrow without prefix
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'jimeh/tmux-themepack'
set -g @themepack 'powerline/default/cyan'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run -b '~/.tmux/plugins/tpm/tpm'
```

`~/.zshrc` or equivalent:

```text
# for tmuxinator window names
export DISABLE_AUTO_TITLE=true
```

Then reload terminal or `source ~/.zshrc` (or equivalent).

Then `tmux source ~/.tmux.conf`

Start up tmux for first time and install the packages in `~/.tmux.conf`:

>  Press prefix + I (capital i, as in Install) to fetch the plugin.

Prefix is usually `CTRL + B`, but it's been changes to `CTRL + A` in config above, to be closer together.

I use a config similar to this. The main projects with two terminals, top is host machine and bottom is inside the container.
A couple tabs/windows for monitoring app logs and database query logs.

`work.yml`:

```yaml
name: work
session_name: work
startup_window: crm
startup_pane: 0
on_project_start: docker-compose -f /home/ally/development/docker-compose.yml up -d
windows:
    - crm:
        layout: tiled
        root: /home/ally/development/html/crm
        panes:
            - host:
                - clear
            - guest:
                - clear
                - make shell
    - api:
        layout: tiled
        root: /home/ally/development/html/api
        panes:
            - host:
                - clear
            - guest:
                - clear
                - make shell
    - mem:
        layout: tiled
        root: /home/ally/development/html/mem
        panes:
            - host:
                - clear
            - guest:
                - clear
                - make shell
    - home:
        layout: tiled
        root: /home/ally/development/html/home
        panes:
            - host:
                - clear
            - guest:
                - clear
                - make shell
    - misc:
        layout: tiled
        root: /home/ally/development/html
        panes:
            - host:
                - clear
            - guest:
                - clear
                - docker exec -it -u $(id -u) -w /var/www/html/ misc bash
    - 'logs:mysql':
        layout: tiled
        panes:
            - main:
                - clear
                - "docker exec -it db bash -c 'tail -fn10 /var/log/mysql/mysql.log'"
            - test:
                - clear
                - "docker exec -it db_testing bash -c 'tail -fn10 /var/log/mysql/mysql.log'"
    - 'logs:app':
        layout: tiled
        root: /home/ally/development
        panes:
            - logs:
                - clear
                - docker-compose logs --follow
```

If `tmuxinator start -p /home/ally/development/work.yaml` is too verbose for you (it is), lets make a shortcut.

`~/.zshrc` or equivalent:

```shell script
function work
{
    tmuxinator start -p /home/ally/development/work.yaml
}
```

Then when you want to get to work, just type `work` in terminal, and boom - all your projects terminals will be there
just after `docker-compose up -d` has done its thing.

You can read more about the tmuxinator [hooks](https://www.rubydoc.info/gems/tmuxinator/Tmuxinator/Hooks/Project) here.
Before I knew about this my alias used to look something like this:

```bash
docker-compose \
    -f /home/ally/development/docker-compose.yml \
    up -d

tmux kill-session -t work
tmuxp load /home/ally/development/work.yaml
```
