---
title: "tmux, tpm, and tmuxinator"
author: "Ally"
summary: "Some notes on `tmux`, `tpm` and `tmuxinator`"
publishDate: 2022-09-21T19:24:50+0100
draft: true
---

Some notes on `tmux`, `tpm`, `tmuxinator`.

## Installation

* [Installing `tpm`](https://github.com/tmux-plugins/tpm#installation)
* [Installing `tmux`](https://github.com/tmux/tmux/wiki/Installing)
* [Installing `tmuxinator`](https://github.com/tmuxinator/tmuxinator#installation)

## tmux

{{< accordion title="Example config" >}}

`~/.tmux.conf`:

```bash
# CTRL + A for prefix
set-option -g prefix ^a

# switch panes using Alt-arrow without prefix
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# split panes using | and -
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'jimeh/tmux-themepack'
set -g @themepack 'powerline/default/cyan'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run -b '~/.tmux/plugins/tpm/tpm'
```
{{< /accordion >}}

After creating `~/.tmux.conf`, open a tmux server with `tmux` then run `tmux source ~/.tmux.conf`.

## tmuxinator
