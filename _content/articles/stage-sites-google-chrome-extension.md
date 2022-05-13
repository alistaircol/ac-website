---
title: "Google Chrome extension to show all dev sites & related info."
summary: "A very basic extension which lists all stage sites for each project, including links and `git` info."
date: 2020-01-20T00:00:00+01:00
draft: true
tags: ['php', 'html', 'js', 'git', 'chrome']
---

{{< alert "danger" >}}
Will be deleted, a better replacement is WIP.
{{< /alert >}}

**TODO**

Screenshots

---

# Introduction/Rationale

We have three dev sites setup for some of our projects to allow QA to test.

* stage
* dev1
* dev2

Some of our projects have a multisite configuration. So project `members` is live at `members.ac93.uk`, the staging setups are `stage.members.ac93.uk`, `dev1.members.ac93.uk`, `dev2.members.ac93.uk` etc. If this project is a multisite setup then we also have things like `vip-members.ac93.uk`, these are setup to do different things like skip certain steps, show different style/layout, etc. Some projects have a few of these variants, so there's quite alot of links to remember and tweak if you need to go test something on there.

So we have a fairly basic page built by a simple PHP script by a cron on our staging server which, for each project does a few things:

**Get current `git` branch:**

```php
git branch --no-color | awk '/*/ {print $2}'
```

Explanation: `git branch` lists all local branches, with an `*` next to the current branch.

```
$ git branch --no-color
* master
```

We'll look for the `*` and print the second word.

```
$ git branch --no-color | awk '/*/ {print $2}'
master
```

Our branch names usually contain a ticket ID from Jira, so easy to see what feature/fix is on there.

**Get last remote commit time:**

```php
git log -1 --format=%cd | cut -d "+" -f 1
```

`git log -1` will get the last `1` commits.

```
$ git log -1
commit 87ac8f8a4a5efb9eac3bebf1da06a8b0409f1452 .....
Author: alistaircol <alistaircol@redacted>
Date:   Mon Jan 20 23:11:09 2020 +0000

    started chrome extension article
```

We can change the format of this output with `--format`. I chose `'%cd'` which is `committer date (format respects --date= option)`, you can see all possible formats in the [git log format specifiers](https://git-scm.com/docs/pretty-formats#Documentation/pretty-formats.txt-cd) documentation.

```
$ git log -1 --format='%cd'
Mon Jan 20 23:11:09 2020 +0000
```

Then `cut -d "+" -f 1` basically removes the timezone part.

```
$ git log -1 --format='%cd' | cut -d "+" -f 1
Mon Jan 20 23:11:09 2020
```

Just from a quick glance we can see if the code is old and needs a pull on stage server.

**Get (Laravel) framework version:**

```bash
php artisan --version
```

This is handy for devs, for example we're testing an upgrade of a framework we can easily see if this projects dev site is out of date.

## PHP / Building a Manifest

Our script starts with information about the projects we care about and any multisites in the project, tailored for the particular dev site.

```php
<?php
$sites = [
  'members' => [   // project name to which all dev sites belong
    'members' => [ // project location in /var/www/html
      'urls' => [  // for adding links to manifest, key = pretty name, value = value
        'Payments' => 'https://stage.payments.ac93.uk',
        'Applications' => 'https://stage.applications.ac93.uk',
        'Members' => 'https://stage.members.ac93.uk',
        'Members: VIP' => 'https://stage.vip-members.ac93.uk',
      ]
    ],
    'dev1-members' => [
      'urls' => [
        'Payments' => 'https://dev1.payments.ac93.uk',
        'Applications' => 'https://dev1.applications.ac93.uk',
        'Members' => 'https://dev1.members.ac93.uk',
        'Members: VIP' => 'https://dev1.vip-members.ac93.uk',
      ]
    ],
    'dev2-members' => [
      'urls' => [
        'Payments' => 'https://dev2.payments.ac93.uk',
        'Applications' => 'https://dev2.applications.ac93.uk',
        'Members' => 'https://dev2.members.ac93.uk',
        'Members: VIP' => 'https://dev2.vip-members.ac93.uk',
      ]
    ],
  ],
  'api' => [
    'api'  => [
      'urls' => [
        'API' => 'https://stage.api.ac93.uk',
      ],
    ],
    'dev1-api'  => [
      'urls' => [
        'API' => 'https://dev1.api.ac93.uk',
      ],
    ],
    'dev2-api'  => [
      'urls' => [
        'API' => 'https://dev2.api.ac93.uk',
      ],
    ],
  ],
  'crm' => [
    'crm' => [
      'urls' => [
        'CRM' => 'https://stage.crm.ac93.uk',
      ],
    ],
    'dev1-crm' => [
      'urls' => [
        'CRM' => 'https://dev1.crm.ac93.uk',
      ],
    ],
    'dev2-crm' => [
      'urls' => [
        'CRM' => 'https://dev2.crm.ac93.uk',
      ],
    ],
  ],
];
```

We'll save the information we find out about the sites into `$manifest`. Later on we'll build a html template from this.

```php
<?php
$manifest['members'] = [];
foreach ($sites['members'] as $site => $info) { // i.e. stage, dev1, dev2
  chdir(sprintf('/var/www/html/%s', $site));
  $record = [
    'site' => $site,
    'urls' => $info['urls'] ?? [],
    'branch' => exec($command_current_branch), // see above
    'last_commit' => exec($command_last_commit), // see above
    'framework_version' => exec($command_laravel_version), // see above
  ];
  $manifest['members'][] = $record;
}
```

Do the same for each project required, some tweaks are made between different frameworks, etc.

Now we have all the information collected into `$manifest` we can build a template.

Originally I went with producing a JSON output (**recommended**), but ultimately produced a HTML manifest because it was ~~easier~~ quicker for me to get it looking nice in the Chrome extension. Javascript templating isn't one of my favourites. Enjoy... 


```php
<?php
$button_format = <<<html
<div class="btn-group btn-block" role="group">
  <button
    type="button"
    class="btn btn-sm btn-success text-left text-truncate"
    data-toggle="tooltip"
    data-placement="top"
    title=""
    data-original-title="%s">
    %s
  </button>
  <div class="btn-group" role="group">
    <button
      id="%s"
      type="button"
      class="btn btn-success btn-sm dropdown-toggle"
      data-toggle="dropdown"
      aria-haspopup="true"
      aria-expanded="false">
    </button>
    <div class="dropdown-menu dropdown-menu-right" aria-labelledby="%s">
      %s
    </div>
  </div>
</div>
html;

$link_format = <<<html
<a class="dropdown-item" target="_blank" href="%s" data-toggle="tooltip" data-placement="top" title="" data-original-title="%s">%s</a>
html;

$table = <<<html
<table class="table table-hover">
  <thead>
    <tr>
      <th scope="col">Project</th>
      <th scope="col">stage</th>
      <th scope="col">dev1</th>
      <th scope="col">dev2</th>
    </tr>
  </thead>
  <tbody>
html;

$html = '';
$html .= $table;

foreach ($manifest as $site => $info) {// i.e. site: stage.members.ac93.uk, dev1.stage.. etc.
  $html .= '<tr>';
  $html .= '<td>' . $site . '</td>';

  foreach ($info as $dev_site) {// from $manifest['members'][] = $record;
    $links = '';
    foreach ($dev_site['urls'] as $name => $url) {
      $links .= vsprintf($link_format, [
        $url,
        $name,
        $url,
      ]);
    }

    $site_info = '';
    if (!$dev_site['framework_version']) {
      $site_info = $dev_site['last_commit'];
    } else {
      $site_info = $dev_site['framework_version'] . ' - ' . $dev_site['last_commit'];
    }

    $cell = vsprintf($button_format, [
      $site_info,
      $dev_site['branch'],
      md5($site . $dev_site['site']), // id for button and tooltips
      md5($site . $dev_site['site']), // id for button and tooltips
      $links,
    ]);

    $col = '<td>' . $cell . '</td>';
    $html .= $col;

  }

  $html .= '</tr>';
}

$html .= '</tbody></table>';

echo $html;
```

All done, ain't pretty but it's a quick and dirty script!

Script is run from cron and manifest put to some public location for the extension to retrieve:
 
```php
php /var/tasks/stage-sites.php > /var/www/html/members/public/stage-sites.html
```

## `jq` - building manifest a better way

Truncated, but better.

```shell script
#!/usr/bin/env bash
jq  -n \
    --arg stage_crm_branch "$(git -C /var/www/html/crm/ symbolic-ref --short HEAD)" \
    --arg stage_crm_commit "$(git -C /var/www/html/crm log -1 --pretty='%cd %B' --date=format:'%d/%m/%Y %H:%M:%S')" \
    --arg stage_crm_version "$(php /var/www/html/crm/artisan --version)" \
    "$(
    cat <<"EOF"
{
    core: {
        stage: {
            branch:  $stage_core_branch,
            commit:  $stage_core_commit,
            version: $stage_core_version,
        },
    }
}
EOF
    )"

```

## Chrome Extension Stuff

The main attraction. For more info see [Develop Extensions Developer Guide](https://developer.chrome.com/extensions/devguide).

Each Chrome extension starts with a `manifest.json`, it'll look something like this:

```json
{
    "name": "AC93",
    "version": "1.0",
    "description": "Show dev sites and their details.",
    "browser_action": {
        "default_popup": "index.html",
        "default_title": "Development Sites"
    },
    "permissions": [
        "https://stage.members.ac93.uk/"
    ],
    "icons": {
        "16": "img/logo-16.png",
        "48": "img/logo-48.png",
        "128": "img/logo-128.png"
    },
    "manifest_version": 2
}
```

Looking at the `manifest.json` things are fairly straightforward. `browser_action`'s `default_popup` is the location within the context of the extension which shows when you click the extension icon in the browser. the `default_title` is the text shown when you hover over the icon.

`permissions` require you to list the domains you need to fetch stylesheets or other assets. Including references to assets or making XHR calls will be blocked without this. In our case add this because we need to use javascript XHR to include the HTML manifest into the page. We don't need to fetch any assets, we'll discuss this next.

`index.html`, the main attraction, is very straightforward:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="css/bootstrap.min.css">
    <link rel="stylesheet" href="css/extension.css">
  </head>
  <body>

    <div class="manifest"></div>

    <script src="js/jquery-3.4.1.slim.min.js"></script>
    <script src="js/popper.min.js"></script>
    <script src="js/bootstrap.min.js"></script>
    <script src="js/extension.js"></script>
  </body>
</html>
```

As you can see we are including bootstrap, and its prerequisites with the extension, so we don't need to fetch these every time we want to use it.

Our `js/extension.js` does the rest of the work.

```js
var manifest = undefined;

var xhr = new XMLHttpRequest();
xhr.open('GET', 'https://stage.members.ac93.uk/stage-sites.html');
xhr.onload = function () {
  if (xhr.status === 200) {
    $('.manifest').html(xhr.response); // load in dom
  }
};

$(document).ready(function () {
  // open any new links from extension into new tabs
  $('body').on('click', 'a', function () {
    chrome.tabs.create({ url: $(this).attr('href') });
    return false;
  });

  // load manifest
  xhr.send();
});

// setup bootstrap tooltips
$(document).ready(function() {
  $("body").tooltip({
    selector: '[data-toggle=tooltip]'
  });
});
```

That's it really! It's just including some html in the page at the end of the day. It could be better if it was a json and you could build frontend to show the same result.

I find it really handy to have this accessible at a seconds notice, just next to the URL bar. Instead, previously this would be a pinned tab and it didn't include any links.

I haven't deployed to the Chrome store (it's $5 and I'm cheap..) but here are some straightforward instructions to install and develop. Maybe I'll get around to this at some point.

## Nuxt/Vue in extension

This would be ideal, better than jquery for me, but can't include that in extension (with nuxt) because of unsafe inline or something.

Local:

* Go to [`chrome://extensions/`](chrome://extensions/)
* Enable developer mode toggle in top right
* Select load unpacked and go to this folder
