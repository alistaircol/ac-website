---
title: "tmux"
author: "Ally"
summary: "tmux setup"
publishDate: 2020-12-29T12:00:00+01:00
tags: ['tmux']
draft: true
---

TODO: screenshot.

Install tmux plugin manager ([`tpm`](https://github.com/tmux-plugins/tpm)) for plugins (obviously) and themes.

My tmux config file is pretty simple, change a couple bindings and load some plugins.

`~/.tmux.conf`:

```text
# https://superuser.com/a/388243
# set default shell as zsh 
# didn't need in plain ubuntu, but required for my regolith instal
set-option -g default-shell /bin/zsh

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

`~/.zshrc` or equivalent:

```shell script
function work
{
    tmuxinator start -p /home/ally/development/work.yaml
}
```
