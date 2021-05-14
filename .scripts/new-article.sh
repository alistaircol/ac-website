#!/usr/bin/env bash
read -rp 'Article Title: ' title
read -rp 'Article Slug: ' slug
read -rp 'Article Description: ' description
read -rp 'Tags (csv with single quote): ' tags

script_directory="${BASH_SOURCE[0]:-$0}"
realpath="$(realpath -s "$script_directory")"
filename="$(dirname "$(dirname "$realpath")")/content/articles/$slug.md"

touch "$filename"

cat <<EOF > "$filename"
---
title: "$title"
author: "Ally"
summary: "$description"
publishDate: $(date --iso-8601=seconds)
tags: [$tags]
draft: true
---
EOF

#---
#title: "A command I've used a few times to install a fresh Laravel project into the cwd's src/ folder, leaving the cwd for your own README, Docker, Terraform, etc. files"
#author: "Ally"
#summary: "A command I've used a few times to install a fresh Laravel project into the cwd's src/ folder, leaving the cwd for your own README, Docker, Terraform, etc. files"
#publishDate: 2021-05-14T19:25:30+01:00
#tags: ['Laravel', 'Docker', 'PHP']
#draft:true
#---
