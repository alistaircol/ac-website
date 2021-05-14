#!/usr/bin/env bash
set -x
read -rp 'Slug:' slug
read -rp 'Description:' description
read -rp 'Tags:' tags

filename="$(dirname "$(pwd)")/content/articles/$slug.md"

touch "$filename"

cat <<EOF > "$filename"
---
title: "$description"
author: "Ally"
summary: "$description"
publishDate: $(date --iso-8601=seconds)
tags: [$tags]
draft:true
---
EOF
