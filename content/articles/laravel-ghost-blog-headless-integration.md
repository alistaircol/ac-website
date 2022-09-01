---
title: "Using Ghost as Headless CMS in a Laravel Site"
author: "Ally"
summary: "How you might integrate content written in a Ghost Blog into a Laravel site using its Content API."
publishDate: 2020-08-29T00:00:00+01:00
tags: ['php', 'laravel', 'ghost']
draft: false
cover: https://ac93.uk/img/articles/laravel-ghost-blog/ghost-create-account.png
---

## Setting up a Ghost Instance

Create an account.

![create-account](/img/articles/laravel-ghost-blog/ghost-create-account.png)

![create-account](/img/articles/laravel-ghost-blog/ghost-create-account-step1.png)

![create-account](/img/articles/laravel-ghost-blog/ghost-create-account-step2.png)

Create an API integration so that our Laravel site can pull content.

![create-integration](/img/articles/laravel-ghost-blog/ghost-integration-step1.png)

![create-integration](/img/articles/laravel-ghost-blog/ghost-integration-step2.png)

## Setting up Ghost Integration in Laravel

First, start with `m1guelpf/ghost-api` into Laravel site.

```bash
composer require m1guelpf/ghost-api
```

Create a Helper for calling the Ghost Blog API.

`app/Helpers/GhostBlog.php`:

```php
<?php

namespace App\Helpers;

use Illuminate\Support\Facades\Cache;
use M1guelpf\GhostAPI\Ghost;

/**
 * Class GhostBlog
 * @see https://github.com/m1guelpf/php-ghost-api#php-ghost-api-client
 */
class GhostBlog
{
    private $api;

    public function __construct()
    {
        $this->api = new Ghost(
            'http://ac_ghost:2368', // ac_ghost is the container_name
            '4a3e3f83d9653bb136429efa69'
        );
    }

    /**
     * @param int $latest
     * @return array
     */
    public static function latest(int $latest): array
    {
        $cache_key = 'ghost_latest_' . $latest;

        if (Cache::has($cache_key)) {
            return Cache::get($cache_key);
        }

        $ghost = new self();
        $response = $ghost->api->getPosts('', '', '', strval($latest));

        try {
            $posts = $ghost->canonicalisePosts($response);
        } catch (\Exception $e) {
            $posts = [];
        } finally {
            Cache::put($cache_key, $posts, 60);
            return $posts;
        }
    }

    /**
     * @param array $response
     * @return array
     * @throws \Exception
     */
    private function canonicalisePosts(array $response): array
    {
        $posts = [];
        if (!array_key_exists('posts', $response)) {
            throw new \Exception('Could not find posts.');
        }
        foreach ($response['posts'] as $post) {
            $posts[] = [
                'title' => $post['title'],
                'created_at' => (new \DateTime($post['created_at']))
                    ->format('d/m/Y H:i:s'),
                'url' => $post['url'],
                'excerpt' => substr(
                    preg_replace(
                        '/\\n/',
                        ' ',
                        $post['excerpt']
                    ),
                    0,
                    100
                ),
            ];
        }
        return $posts;
    }
}
```

Create a blade `section`. Read more about the Ghost Content API [here](https://ghost.org/docs/api/v3/content/).

e.g. `resources/views/parts/homepage-blog.blade.php`:

```php
<div class="container" style="padding-top:20px; margin-bottom: 20px;">
  <h2 class="h2-section-title">Blog</h2>
  <div class="i-section-title"><i class="icon-zoom-in"></i></div>

  <div class="col-md-12 col-sm-12 isotope" id="masonry-elements">
    @if (!isset($posts))
      <p>No posts.</p>
    @else
      @foreach ($posts as $post)
        <div class="feature blog-masonry isotope-item" style="position: absolute; left: 15px; top: 0px;">
          <div class="feature-content" style="background-color: #fff !important;">
            <h3 class="h3-body-title blog-title">
              <a target="_blank" href="{{ $post['url'] }}">
                {{ $post['title'] }}
              </a>
            </h3>
            <p>
              {{ $post['excerpt'] }}&hellip;
            </p>
          </div>

          <div class="feature-details" style="background-color: #fff !important;">
            <i class="icon-calendar"></i>
            <span>{{ $post['created_at'] }}</span>
            <span class="details-seperator"></span>
            <div class="feature-share">
              <a target="_blank" href="{{ $post['url'] }}">
                Read more &raquo;
              </a>
            </div>
          </div>
        </div>
      @endforeach
    @endif
  </div>
</div>
``` 

Use the section:

e.g. `resources/views/index.blade.php`:

```php
@include('parts/homepage-blog', ['posts' => \App\Helpers\GhostBlog::latest(3)])
```

Which might look something like this:

![integration](/img/articles/laravel-ghost-blog/laravel-integration.png)

### Blog Route Service Provider

{{< alert "secondary" >}}
This is not required.
{{< /alert >}}

For the route service provider we need to get a list of slugs.

In `app/Providers/RouteServiceProvider.php`, add `mapBlogRoutes` and don't forget to call it in `map` within the same file:

```php
<?php

class RouteServiceProvider extends ServiceProvider
{
    // ...
    protected function mapBlogRoutes()
    {
        Route::prefix('blog')
            ->group(base_path('routes/blog.php'));
    }
}
```

Now, create `routes/blog.php`:

```php
<?php

use App\Helpers\GhostBlog;
use App\Http\Controllers\GhostBlogPostController;

Route::get('/', GhostBlogPostController::class)->name('index');

try {
    $slugs = GhostBlog::slugs();
    foreach ($slugs as $slug) {
        Route::get($slug, GhostBlogPostController::class)
            ->name($slug);
    }
} catch (Exception $e) {
    \Log::error('Caught ' . get_class($e) . ': ' . $e->getMessage());
}
```

You can see a few things from this:

* New `slugs` function from the `GhostBlog` helper
* New `GhostsBlogPostController`

#### `slugs` helper

Add to `app/Helpers/GhostBlog.php`:

```php
<?php
/**
 * @return array
 * @throws \Exception
 */
public static function slugs(): array
{
    $cache_key = 'ghost_posts_slugs';

    if (Cache::has($cache_key)) {
        return Cache::get($cache_key);
    }

    $ghost = new self();
    $response = $ghost->api->getPosts('', 'slug', '', 'all');

    if (!array_key_exists('posts', $response)) {
        throw new \Exception('Could not find posts.');
    }

    $slugs = array_column($response['posts'], 'slug');
    Cache::put($cache_key, $slugs, 10);

    return $slugs;
}
```

We use the following options for our convenience:

* [`limit`](https://ghost.org/docs/api/v3/content/#limit) = `all` - to save from doing pagination on our side
* [`fields`](https://ghost.org/docs/api/v3/content/#fields) = `slug` - we just care about getting slug, no other information is required. Posts are only shown here when they are visible, i.e. not pending schedule.

![postman-slugs](/img/articles/laravel-ghost-blog/postman-slugs.png)

Run `php artisan route:list` and we can see them!

```text
+--------+----------+------------------------ +-------------------------+----------------------------------------------+
| Domain | Method   | URI                     | Name                    | Action                                       |
+--------+----------+------------------------ +-------------------------+----------------------------------------------+
|        | GET|HEAD | blog/                   | index                   | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/admin-settings     | admin-settings          | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/apps-integrations  | apps-integrations       | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/organising-content | blog/organising-content | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/publishing-options | blog/publishing-options | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/the-editor         | blog/the-editor         | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/themes             | blog/themes             | App\Http\Controllers\GhostBlogPostController |
|        | GET|HEAD | blog/welcome            | blog/welcome            | App\Http\Controllers\GhostBlogPostController |
```

## Blog Routes

Or you could've just done:

`routes/blog.php`:

```php
<?php

Route::get('blog/{?slug}', App\Http\Controllers\GhostBlogPostController::class);
```

And handle that in a similar way...

## Blog Posts Controller

The Posts controller is fairly simple:

`app/Http/Controllers/GhostBlogPostController.php`:

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

use App\Helpers\GhostBlog;

class GhostBlogPostController extends Controller
{
    public function __invoke(Request $request)
    {
        try {
            $slug = $request->route()->getName();

            if ($slug == 'index') {
                // TODO: this is to list all posts,
                // probably will need to use pagination, etc.
            }

            $post = GhostBlog::post($slug);

            return view(
                'blog-post',
                [
                    'post' => $post,
                ]
            );
        } catch (\Throwable $e) {
            return response()->setStatusCode(404);
        }
    }
}
```

Another helper to add to `GhostBlog`:

`app/Helpers/GhostBlog.php`:

```php
<?php

/**
 * @param string $slug
 * @return array|mixed
 * @throws \Exception
 */
public static function post(string $slug)
{
    $cache_key = 'ghost_posts_' . $slug;

    if (Cache::has($cache_key)) {
        return Cache::get($cache_key);
    }

    $ghost = new self();
    // https://ghost.org/docs/api/v3/content/#parameters
    $filter = sprintf('slug:%s', $slug);
    $response = $ghost->api->getPosts('', '', $filter, '1');

    if (!array_key_exists('posts', $response)) {
        throw new \Exception('Could not find posts.');
    }

    if (empty($response['posts'])) {
        throw new NotFoundResourceException('Post ' . $slug . ' does not exist.');
    }

    $post = $response['posts'][0];
    Cache::put($cache_key, $post, 60);

    return $post;
}
```

## Blog Posts View

From the controller you can see its view is `blog-post`.

`resources/views/blog-post.blade.php`:

```php
// whatever - use $post
```

```json
{
    "posts": [
        {
            "id": "5f4bde232c7fc30001b765f3",
            "uuid": "6887854a-97ef-429a-819e-6ef859091dd3",
            "title": "Welcome to Ghost",
            "slug": "welcome",
            "html": "<h2 id=\"a-few-things-you-should-know\"><strong>A few things you should know</strong></h2><ol><li>Ghost is designed for ambitious, professional publishers who want to actively build a business around their content. That's who it works best for. </li><li>The entire platform can be modified and customised to suit your needs. It's very powerful, but does require some knowledge of code. Ghost is not necessarily a good platform for beginners or people who just want a simple personal blog. </li><li>It's possible to work with all your favourite tools and apps with hundreds of <a href=\"https://ghost.org/integrations/\">integrations</a> to speed up your workflows, connect email lists, build communities and much more.</li></ol><h2 id=\"behind-the-scenes\">Behind the scenes</h2><p>Ghost is made by an independent non-profit organisation called the Ghost Foundation. We are 100% self funded by revenue from our <a href=\"https://ghost.org/pricing\">Ghost(Pro)</a> service, and every penny we make is re-invested into funding further development of free, open source technology for modern publishing.</p><p>The version of Ghost you are looking at right now would not have been made possible without generous contributions from the open source <a href=\"https://github.com/TryGhost\">community</a>.</p><h2 id=\"next-up-the-editor\">Next up, the editor</h2><p>The main thing you'll want to read about next is probably: <a href=\"http://localhost:2368/the-editor/\">the Ghost editor</a>. This is where the good stuff happens.</p><blockquote>By the way, once you're done reading, you can simply delete the default Ghost user from your team to remove all of these introductory posts! </blockquote>",
            "comment_id": "5f4bde232c7fc30001b765f3",
            "feature_image": "https://static.ghost.org/v3.0.0/images/welcome-to-ghost.png",
            "featured": false,
            "visibility": "public",
            "send_email_when_published": false,
            "created_at": "2020-08-30T17:13:07.000+00:00",
            "updated_at": "2020-08-30T17:13:07.000+00:00",
            "published_at": "2020-08-30T17:13:13.000+00:00",
            "custom_excerpt": "Welcome, it's great to have you here.\nWe know that first impressions are important, so we've populated your new site with some initial getting started posts that will help you get familiar with everything in no time.",
            "codeinjection_head": null,
            "codeinjection_foot": null,
            "custom_template": null,
            "canonical_url": null,
            "url": "http://localhost:2368/welcome/",
            "excerpt": "Welcome, it's great to have you here.\nWe know that first impressions are important, so we've populated your new site with some initial getting started posts that will help you get familiar with everything in no time.",
            "reading_time": 1,
            "access": true,
            "og_image": null,
            "og_title": null,
            "og_description": null,
            "twitter_image": null,
            "twitter_title": null,
            "twitter_description": null,
            "meta_title": null,
            "meta_description": null,
            "email_subject": null
        }
    ],
    "meta": {
        "pagination": {
            "page": 1,
            "limit": 1,
            "pages": 1,
            "total": 1,
            "next": null,
            "prev": null
        }
    }
}
```

`.posts[0]` is sent to view to do whatever you want with.

### Configuring Ghost URL

As you can see from some of the links, these will need to be rewritten.

* `ghost` cli tool, more info [here](https://ghost.org/docs/concepts/config/)

Or scan through each value in the post response and manually rewrite (yuck).

## Complete `GhostBlog` helper

```php
<?php

namespace App\Helpers;

use Illuminate\Support\Facades\Cache;
use M1guelpf\GhostAPI\Ghost;
use Symfony\Component\Translation\Exception\NotFoundResourceException;

/**
 * Class GhostBlog
 * @see https://github.com/m1guelpf/php-ghost-api#php-ghost-api-client
 */
class GhostBlog
{
    private $api;

    public function __construct()
    {
        $this->api = new Ghost(
            'http://qa_ghost:2368',
            '4a3e3f83d9653bb136429efa69'
        );
    }

    /**
     * @param int $latest
     * @return array
     */
    public static function latest(int $latest): array
    {
        $cache_key = 'ghost_latest_' . $latest;

        if (Cache::has($cache_key)) {
            return Cache::get($cache_key);
        }

        $ghost = new self();
        $response = $ghost->api->getPosts('', '', '', strval($latest));

        try {
            $posts = $ghost->canonicalisePosts($response);
        } catch (\Exception $e) {
            $posts = [];
        } finally {
            Cache::put($cache_key, $posts, 60);
            return $posts;
        }
    }

    /**
     * @return array
     * @throws \Exception
     */
    public static function slugs(): array
    {
        $cache_key = 'ghost_posts_slugs';

        if (Cache::has($cache_key)) {
            return Cache::get($cache_key);
        }

        $ghost = new self();
        $response = $ghost->api->getPosts('', 'slug', '', 'all');

        if (!array_key_exists('posts', $response)) {
            throw new \Exception('Could not find posts.');
        }

        $slugs = array_column($response['posts'], 'slug');
        Cache::put($cache_key, $slugs, 10);

        return $slugs;
    }

    /**
     * @param string $slug
     * @return array|mixed
     * @throws \Exception
     */
    public static function post(string $slug)
    {
        $cache_key = 'ghost_posts_' . $slug;
    
        if (Cache::has($cache_key)) {
            return Cache::get($cache_key);
        }
    
        $ghost = new self();
        // https://ghost.org/docs/api/v3/content/#parameters
        $filter = sprintf('slug:%s', $slug);
        $response = $ghost->api->getPosts('', '', $filter, '1');
    
        if (!array_key_exists('posts', $response)) {
            throw new \Exception('Could not find posts.');
        }
    
        if (empty($response['posts'])) {
            throw new NotFoundResourceException('Post ' . $slug . ' does not exist.');
        }
    
        $post = $response['posts'][0];
        Cache::put($cache_key, $post, 60);
    
        return $post;
    }

    /**
     * @param array $response
     * @return array
     * @throws \Exception
     */
    private function canonicalisePosts(array $response): array
    {
        $posts = [];
        if (!array_key_exists('posts', $response)) {
            throw new \Exception('Could not find posts.');
        }
        foreach ($response['posts'] as $post) {
            $posts[] = [
                'title' => $post['title'],
                'created_at' => (new \DateTime($post['created_at']))
                    ->format('d/m/Y H:i:s'),
                'url' => $post['url'],
                'excerpt' => substr(
                    preg_replace(
                        '/\\n/',
                        ' ',
                        $post['excerpt']
                    ),
                    0,
                    100
                ),
            ];
        }
        return $posts;
    }
}

```


### Other Considerations

If configuring the site URL is difficult, you might need to scrape the content and replace the internal links to that of the site you want to host on.
