#!/usr/bin/env bash
read -rp 'Article Slug: ' slug
read -rp 'Article Title: ' title
read -rp 'Article Description: ' description
read -rp 'Tags (csv with single quote): ' tags

# realpath: command not found
# ughh.
# brew install coreutils
script_directory="${BASH_SOURCE[0]:-$0}"
realpath="$(realpath -s "$script_directory")"
filename="$(dirname "$(dirname "$realpath")")/content/articles/$slug.md"

touch "$filename"

cat <<EOF > "$filename"
---
title: "$title"
author: "Ally"
summary: "$description"
publishDate: $(date +%Y-%m-%dT%H:%M:%S%z)
tags: [$tags]
draft: true
---
EOF
