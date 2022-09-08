---
title: "Adding asynchronous search to a hugo blog"
author: "Ally"
summary: "Learn how to add asynchronous search to a hugo blog with alpine and fuse"
publishDate: 2022-09-08T19:24:50+0100
tags: ['hugo','alpine','fuse']
cover: https://ac93.uk/img/articles/hugo-search-fuse-alpine/search-results.png
---

I have wanted to add search on my blog for some time. When I was certain I had written about a tool I had used some, or looking for a code snippet, but I couldn't remember under which post it was mentioned, I would go to this website's [github repo](https://github.com/alistaircol/ac-website) and do a search there. Obviously this was very inconvenient. Back when I first started this site, the template I chose [`zwbetz-gh/papercss-hugo-theme`](https://github.com/zwbetz-gh/papercss-hugo-theme) didn't have it built in.

I recently have redesigned this site, so I have gotten more familiar with how `hugo` works under the bonnet, even if it's mostly changing something and see what happens until I get the desired results!

![search results](/img/articles/hugo-search-fuse-alpine/search-results.png)

## Search in Hugo

I looked at hugo's website on [searching](https://gohugo.io/tools/search/) and found the following [gist](https://gist.github.com/eddiewebb/735feb48f50f0ddd65ae5606a1cb41ae) as inspiration.

I was able to see from the start that I would have to make a bunch of changes to get it to work how I would like.

I wanted to have asynchronous search results, so I decided upon the following changes:

* In the gist's [`layouts/_default/search.html`](https://gist.github.com/eddiewebb/735feb48f50f0ddd65ae5606a1cb41ae#layouts_defaultsearchhtml) I will add the search form and results instead to my `articles/list.html`, since it's only content under `articles/` I want to search from the `articles` section's `list` page.
* In the gist's [`static/js/search.js`](https://gist.github.com/eddiewebb/735feb48f50f0ddd65ae5606a1cb41ae#staticjssearchjs) I will use [`fuse`](https://fusejs.io/), but not `mark`, therefore reducing the complexity. Also, since I'm doing async search, I do not serve this static `js/search.js` file, instead there is a tiny alpine component which handles the search of the manifest in fuse. I use alpine for it's templating because it's lightweight, and something I am familiar and comfortable using. Javascript is definitely not my forte.
* In the gist's [`layouts/_default/index.json`](https://gist.github.com/eddiewebb/735feb48f50f0ddd65ae5606a1cb41ae#layouts_defaultindexjson) I will add some new fields, to make rendering the search results a little more fancy and easier.

## Building a 'search manifest'

The search component [`fuse`](https://fusejs.io/) has a pretty simple API:

* give it a bunch of data
* give it some config

But more on `fuse` later.

As per the gist, you need to add `JSON` output in your hugo's config file.

For me this is in [`config/_default/config.yaml`](https://github.com/alistaircol/ac-website/blob/fa0b03bdba9c9fe073834a04681b484000479138/config/_default/config.yaml) (I'm not a huge fan of `toml`):

```diff
 outputs:
   section:
   - HTML
   - RSS
+  - JSON
```

This will build a file at `index.json` for each section (only if you change to place it in `layouts/_default/section.json`), e.g. `http://localhost:1313/articles/index.json`.

For me, there was no layout file for [`JSON`](https://gohugo.io/templates/output-formats/) for kind `section, so we'll sort that next.

## Section `index.json`

For the search integration to work we need to build the `index.json`.

I altered the gist's suggestion with the following changes:

* Remove categories - I don't use them personally.
* Change `content` from [`.Plain`](https://gohugo.io/variables/page/#page-variables) which returns html, to `.RawContent | plainify` which runs the markdown through [plainify](https://gohugo.io/functions/plainify/) which strips any html tags that may be there.
* Add `canonical tags`, which is basically set of tuples containing the tag name and permalink of the tag page from `.Params.tags`.
* Add formatted estimated reading time from `.ReadingTime`.
* Add published date, machine-readable, and human-readable variants from `.PublishDate`.

I don't really understand the syntax differences between `{{ }}` and `{{- -}}`, I think it's something to do with line-breaks.

Some resources on functions/variables in the layout:

* [`Scratch`](https://gohugo.io/functions/scratch/)
* [`dict`](https://gohugo.io/functions/dict/)
* [`printf`](https://gohugo.io/functions/printf/)
* [`urlize`](https://gohugo.io/functions/urlize/)
* [`absURL`](https://gohugo.io/functions/absurl/)
* [`plainify`](https://gohugo.io/functions/plainify/)
* [`cond`](https://gohugo.io/functions/cond/)
* [`jsonify`](https://gohugo.io/functions/jsonify/)

For me, this file is at [`layouts/articles/section.json`](https://github.com/alistaircol/ac-website/blob/fa0b03bdba9c9fe073834a04681b484000479138/layouts/articles/section.json):

```go
{{- $.Scratch.Add "index" slice -}}
{{- $pages := .Pages -}}
{{- range $pages.ByPublishDate.Reverse -}}
    {{- $.Scratch.Add "canonical_tags" slice -}}
    {{- $tags := .Params.tags -}}
    {{- range $tags -}}
        {{- $.Scratch.Add "canonical_tags" (dict "url" ((printf "tags/%s" . | urlize) | absURL) "name" .) -}}
    {{- end -}}
{{- $.Scratch.Add "index" (dict
        "title" .Title
        "tags" .Params.tags
        "categories" .Params.categories
        "summary" .Summary
        "permalink" .Permalink
        "content" (.RawContent | plainify)
        "reading_time" (printf "~%d minute%s" .ReadingTime (cond (eq .ReadingTime 1) "" "s"))
        "canonical_tags" ($.Scratch.Get "canonical_tags")
        "date_published" (.PublishDate.Format "Mon, 02 Jan 2006 15:04")
        "date_published_machine" (.PublishDate.Format "2006-01-02 15:04")) -}}
    {{- $.Scratch.Delete "canonical_tags" -}}
{{- end -}}
{{- $.Scratch.Get "index" | jsonify -}}
```

You may need to restart your `hugo` server for this layout to be applied, with all going well, you should see a file now e.g. `http://localhost:1313/articles/index.json`. It will look something like this:

```json
[
  {
    "canonical_tags": [
      {
        "name": "laravel",
        "url": "https://ac93.uk/tags/laravel"
      },
      {
        "name": "github",
        "url": "https://ac93.uk/tags/github"
      },
      {
        "name": "phpunit",
        "url": "https://ac93.uk/tags/phpunit"
      }
    ],
    "categories": null,
    "content": "very long string",
    "date_published": "Mon, 05 Sep 2022 17:40",
    "date_published_machine": "2022-09-05 17:40",
    "permalink": "https://ac93.uk/articles/laravel-github-workflow-lint-run-unit-and-feature-tests-and-generate-code-coverage-report/",
    "reading_time": "~8 minutes",
    "summary": "Create and configure a GitHub workflow to run PHP QA tools (e.g. <code>phplint</code>, <code>phpcs</code>), and then run unit and feature tests (e.g. <code>php artisan test</code>, <code>phpunit</code>), and finally generate a code coverage report or some other artifact.",
    "tags": [
      "laravel",
      "github",
      "phpunit"
    ],
    "title": "Create a GitHub workflow to run PHP linters, tests, and generate coverage report"
  }
  // more
]
```

The output is pretty 'minified', so I found this [chrome extension](https://chrome.google.com/webstore/detail/json-formatter/bcjindcccaagfpapjjmafapmmgkkhgoa/related?hl=en) could be helpful to debug.

## Script slot in `baseof.html`

As mentioned, I add the search input and result in article list page.

Firstly, I added a 'slot' into `layouts/_default/baseof.html`, so we can load some scripts only on this `/articles` page.

e.g. `layouts/_default/baseof.html`:

```html
<!DOCTYPE html>
<html lang="{{ .Site.Language.Lang }}" class="dark">
    {{ partial "head.html" . }}
    <body id="top">
        <main>
            {{ block "main" . }}{{ end }}
        </main>
    </body>
    
    {{ block "scripts" . }}{{ end }}
</html>
```

## Alpine search component

I use [alpine](https://alpinejs.dev/) as a lightweight component to initiate the search and display the search results.

```js {linenos=true}
function searchState() {
    return {
```

I set a `manifest` variable to the absolute URL generated at build time, and add a cache-busting query parameter.

```js {linenos=true, linenostart=3}
        manifest: '{{ "articles/index.json" | absURL }}?q={{ now.Unix }}',
```

I use `query` as the 'model' in the page to get the search input.

```js {linenos=true, linenostart=4}
        query: '',
        fuseOptions: {
```

I use the default fuse options, except the following ones mentioned below.

I set the following [weights](https://fusejs.io/examples.html#weighted-search) for the following attributes.

The weight value has to be greater than `0`. When a weight isn't provided, it will default to `1`.

```js {linenos=true, linenostart=6}
            keys: [
                {
                    name: "title",
                    weight: 0.8
                },
                {
                    name: "content",
                    weight: 2
                },
                {
                    name: "tags",
                    weight: 0.5
                }
            ],
```

I change the [`threshold`](https://fusejs.io/api/options.html#threshold) - the point does the match algorithm give up - to have a bit more precision but potentially a little lower recall. It seems to be a good setting for me at the moment.

A threshold of `0.0` requires a perfect match (of both letters and location), a threshold of `1.0` would match anything. The default is `0.6`.

```js {linenos=true, linenostart=20}
            threshold: 0.3,
```

I change the [`ignoreLocation`](https://fusejs.io/api/options.html#ignorelocation) from its default `false` to `true`. This means it will search the entire content.

```js {linenos=true, linenostart=21}
            ignoreLocation: true,
        },
```

I will save the search results from fuse here, so we can render them later.

```js {linenos=true, linenostart=23}
        searchResults: [],
```

When there are search results, I render a link with the search query in, e.g. `articles/?s=laravel`, meaning a search result page can be shared.

```js {linenos=true, linenostart=24}
        init() {
            this.query = new URLSearchParams(location.search).get('s') || '';
            if (this.query.length > 0) {
                this.search();
            }
        },
```

Fairly simple search function which gets run on form submit.

```js {linenos=true, linenostart=30}
        search() {
            fetch(this.manifest)
                .then((response) => response.json())
                .then((data) => {
                    let fuse = new Fuse(data, this.fuseOptions);
                    let results = fuse.search(this.query);
                    this.searchResults = results;
                });
        }
    };
}
```

You can see the code for the component without annotations [here](https://github.com/alistaircol/ac-website/blob/fa0b03bdba9c9fe073834a04681b484000479138/layouts/articles/list.html#L8).

## Section `list.html`

As mentioned earlier, the asynchronous search input and results will go in my [`layouts/articles/list.html`](https://github.com/alistaircol/ac-website/blob/fa0b03bdba9c9fe073834a04681b484000479138/layouts/articles/list.html) page.

```html
<section id="search" x-data="searchState()" class="my-6">
    <form action="{{ .Permalink }}" x-on:submit.prevent="search">
        <div class="">
            <div class="">
                <svg 
                    aria-hidden="true"
                    class=""
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg">
                    <path 
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z">
                    </path>
                </svg>
            </div>
            <input
                type="search"
                id="default-search"
                placeholder="Search term..."
                required=""
                x-model="query"
                class="">
            <button
                type="submit"
                class="">Search</button>
        </div>
    </form>

    <!-- todo: render searchResults as you wish -->
</section>
```

I won't go into great detail on rendering the search results, instead you can see my layout [here](https://github.com/alistaircol/ac-website/blob/fa0b03bdba9c9fe073834a04681b484000479138/layouts/articles/list.html#L89).

## Search dependencies

Since we created the `scripts` block in `layouts/_default/baseof.html` we will utilise that now in `layouts/articles/list.html`:

```html
{{ define "scripts" }}
<script defer src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js"></script>
<script derfer src="https://cdn.jsdelivr.net/npm/fuse.js@6.6.2"></script>
{{ end }}
```

## Utterances

I also have added [utteranc.es](https://utteranc.es/) integration, which was very easy and doesn't merit much more than the script goes the above-mentioned `scripts` block in the `layouts/articles/list.html`.

Hope this can be helpful to anyone!
