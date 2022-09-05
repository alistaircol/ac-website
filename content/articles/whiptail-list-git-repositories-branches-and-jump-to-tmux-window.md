---
title: "Using whiptail to show the active git branch for a set of git repositories"
author: "Ally"
summary: "List the active `git branch` for a set of `git` repositories in `whiptail`, then jump to the selected repository's `tmux` window"
publishDate: 2022-06-06T20:18:44+0100
tags: ['git', 'tmux', 'whiptail']
cover: https://ac93.uk/img/articles/whiptail-git-branches-tmux/whiptail-tmux-list.png
---

## Preamble

My day job requires working across multiple repositories. Often more than one repository needs to be on the same branch when I'm working on a feature.

Tangentially, I use [`tmux`](https://github.com/tmux/tmux) and [`tmuxinator`](https://github.com/tmuxinator/tmuxinator) to have a window for each repository and some for monitoring, etc. I often jump between windows (i.e. repositories) and see the active [`git branch`](https://git-scm.com/docs/git-branch) from the command line (I use [`ohmyzsh`](https://github.com/ohmyzsh/ohmyzsh) with the [`ys`](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes#ys) theme).

Install on Mac:

```bash
brew install newt
```

## Script (step by step)

```bash {linenos=true}
# list of repository roots
paths=(
    # todo: add your repositories here
)
```

Here you should add absolute path to repository roots, i.e. `"/home/ally/development/ac-website"`.

```bash {linenos=true linenostart=6}
# from the repository roots we will get the branch name
declare -A branches=()
```

The `declare` will create a variable named `branches`, the [`-A`](https://ss64.com/bash/declare.html) designates this as an associative array/hashmap. We will use this to store the active branch for the repository root.

```bash {linenos=true linenostart=9}
# populate repository roots branches
for p in "${paths[@]}"; do
    k="$(basename "$p")"
    branches[$k]="$(git -C "$p" branch --show-current)"
done
```

It will look something like this:

```php
$branches = [
    "/home/ally/development/ac-website" => "main"
]
```

Next we will do some calculations to determine size of the [`whipatail`](https://linux.die.net/man/1/whiptail) radio list.

**Note:** this has `zsh`isms, `${(@k)branches[*]}` is different to bash syntax (to list the keys of the array, in `bash` I believe you would substitute with `${!branches[*]}`).

```bash {linenos=true, linenostart=15, hl_lines=[5,6]}
items="${#paths[@]}"
height=$((items * 2))

# calculate width of box depending on repository and branch names
w_repo=$(echo "${(@k)branches[*]}" | tr " " "\n" | awk '{ print length($0) }' - | sort -rn | head -n1)
w_branch=$(echo "${branches[*]}" | tr " " "\n" | awk '{ print length($0) }' - | sort -rn | head -n1)
width=$((w_repo + w_branch + 15))
```

Highlighted lines will (not in a bulletproof manner):

* split words (i.e. branches or repository root) into separate lines
* print the length of each word
* sort the lines (word lengths) in reverse numeric order, i.e. descending (the highest first, the lowest last)
* get the first line, i.e. the highest number

```bash {linenos=true, linenostart=23}
# make the command (trailing space for concatenating tag item status tuples
cmd="whiptail \
    --title=\"Repository branches\" \
    --backtitle=\"Relevant repository branches\" \
    --ok-button=\"Change Window\" \
    --cancel-button=\"Ok\" \
    --radiolist \"Repository branches\" \
    $height $width $items "
```

The above might not be syntactically correct (I split across lines for readability).

We will concatenate the tuples for the radio list items.

These come in the format: `"tag" "item" status`.

```bash {linenos=true, linenostart=32}
for p in "${(k)paths[@]}"; do
    tag="$(basename "$p")"
    item="${branches[$tag]}"

    cmd+="\"$tag\" "
    cmd+="\"$item\" "
    cmd+="OFF "
done
```

**Note:** this has [`zsh`isms](https://unix.stackexchange.com/a/150041/265713), `${(@k)paths[@]}` is different to bash syntax (to list the keys of the array, in `bash` I believe you would substitute with `${!paths[@]}`).

I tried to iterate through `$branches` instead of `$paths`, but for some reason they were in some random order.

```bash {linenos=true, linenostart=41}
# finish the command
cmd+="3>&1 1>&2 2>&3"
answer=$(eval "$cmd")
```

The `3>&1 1>&2 2>&3` is to grab `stderr` where the answer if chosen (the tag of the radio list item tuple) is outputted from `whiptail` without printing to screen.

Using `eval` is not ideal, but I found it was required.

The following is `tmux` specific things based on the answer to switch windows.

```bash {linenos=true, linenostart=45}
if [[ $TERM_PROGRAM == "tmux" ]]; then
    if [[ "$answer" == "ac-website" ]]; then
        tmux select-window -t 0
    elif [[ "$answer" == "ac-skills" ]]; then
        tmux select-window -t 1
    else
        echo "not sure how to handle this answer in tmux"
    fi
else
    echo "not in tmux, not changing window"
fi
```

## Screenshots

### With tmux

List of all repositories in your list and the active branch:

![whiptail tmux list](/img/articles/whiptail-git-branches-tmux/whiptail-tmux-list.png)

Select a branch (or choose Ok to close):

![whiptail tmux select](/img/articles/whiptail-git-branches-tmux/whiptail-tmux-select.png)

Will change to defined window if in tmux (trust me it does it):

![whiptail tmux answer](/img/articles/whiptail-git-branches-tmux/whiptail-tmux-answer.png)

### Without tmux

![whiptail list](/img/articles/whiptail-git-branches-tmux/whiptail-no-tmux-list.png)

![whiptail answer](/img/articles/whiptail-git-branches-tmux/whiptail-no-tmux-answer.png)


## Complete Code

```bash { linenos=true }
#!/usr/bin/env zsh
# list of repository roots
paths=(
    # todo: add your repositories here
)

# from the repository roots we will get the branch name
declare -A branches=()

# populate repository roots branches
for p in "${paths[@]}"; do
    k="$(basename "$p")"
    branches[$k]="$(git -C "$p" branch --show-current)"
done

items="${#paths[@]}"
height=$((items * 2))

# calculate width of box depending on repository and branch names
w_repo=$(echo "${(@k)branches[*]}" | tr " " "\n" | awk '{ print length($0) }' - | sort -rn | head -n1)
w_branch=$(echo "${branches[*]}" | tr " " "\n" | awk '{ print length($0) }' - | sort -rn | head -n1)
width=$((w_repo + w_branch + 15))

# make the command (trailing space for concatenating tag item status tuples
cmd="whiptail \
    --title=\"Repository branches\" \
    --backtitle=\"Relevant repository branches\" \
    --ok-button=\"Change Window\" \
    --cancel-button=\"Ok\" \
    --radiolist \"Repository branches\" \
    $height $width $items "

# https://unix.stackexchange.com/a/150041/265713
for p in "${(k)paths[@]}"; do
    tag="$(basename "$p")"
    item="${branches[$tag]}"

    cmd+="\"$tag\" "
    cmd+="\"$item\" "
    cmd+="OFF "
done

# finish the command
cmd+="3>&1 1>&2 2>&3"
answer=$(eval "$cmd")

if [[ $TERM_PROGRAM == "tmux" ]]; then
    if [[ "$answer" == "ac-website" ]]; then
        tmux select-window -t 0
    elif [[ "$answer" == "ac-skills" ]]; then
        tmux select-window -t 1
    else
        echo "not sure how to handle this answer in tmux"
    fi
else
    echo "not in tmux, not changing window"
fi
```
