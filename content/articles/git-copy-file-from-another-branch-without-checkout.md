---
title: "Quckie: git - copy a file from another branch without switching branch"
author: "Ally"
summary: "Copy a file from another git branch without checking to that target branch."
publishDate: 2021-06-21T14:57:08+0100
tags: ['git', 'quickie']
draft: false
cover: https://ac93.uk/img/unsplash/yancy-min-842ofHC6MaI-unsplash.jpg
---

Ever wanted to grab a file from another branch in `git`, but don't want to `checkout` to the target branch?

[`git-show`](https://git-scm.com/docs/git-show) to the rescue.

```bash
export BRANCH="123-feature"
export INPUT="app/Http/Livewire/MyComponent.php"
export OUTPUT="MyComponent-123-feature.php"
git show $BRANCH:$FILE > $OUTPUT
```

Or [`git-diff`](https://git-scm.com/docs/git-diff) if you to do that:

```bash
git diff master:app/Http/Livewire/MyComponent.php \
  feature:app/Http/Livewire/MyComponent.php
```

{{< unsplash/git >}}
