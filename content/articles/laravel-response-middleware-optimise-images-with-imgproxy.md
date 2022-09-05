---
title: "A Laravel middleware to optimise images with imgproxy on arbitrary markup"
author: "Ally"
summary: "Create a Laravel middleware to parse the response DOM and update a set of `img`'s `src` to be routed through `imgproxy`."
publishDate: 2022-08-25T12:22:31+0100
tags: ['laravel','imgproxy']
draft: false
---

Recently I had to add `imgproxy` to a section of a Laravel which hosts CMS content through a WYSIWYG and is persisted as html.

I decided to use a middleware to rewrite the content, I used the following (well rated) packages to help:

* [`crocodile2u/imgproxy-php`](https://packagist.org/packages/crocodile2u/imgproxy-php)
* [`pquettg/php-html-parser`](https://packagist.org/packages/paquettg/php-html-parser)

## imgproxy

For local development, I obviously use docker.

The following variables will need to be added to `.env` file for your Laravel project (and they are the same that we will pass to our imgproxy service later):

```.env
IMGPROXY_KEY=
IMGPROXY_SALT=
IMGPROXY_SIGNATURE_SIZE=32
```

For `IMGPROXY_KEY` and `IMGPROXY_SALT` I use the following to generate values:

```bash
echo $(xxd -g 2 -l 64 -p /dev/random | tr -d '\n')
````

I don't need to run it all the time, so this will suffice:

```bash
docker run --rm --env-file /path/to/laravel-site/.env -p 8888:8080 darthsim/imgproxy:latest
```

Since I use valet, I need to proxy since serving http content on https is tricky.

```bash
valet proxy --secure imgproxy.ac93 http://localhost:8888
```

This will mean that `https://imgproxy.ac93.test` will be what will used in the Laravel app to host our images through imgproxy. Add it to the `.env`.

```env
IMGPROXY_URL=https://imgproxy.ac93.test
```

Add the following to a relevant `config` file, e.g. `config/services.php`:

```php
<?php

return [

    'imgproxy' => [
        'url'  => env('IMGPROXY_URL'),
        'salt' => env('IMGPROXY_SALT'),
        'key'  => env('IMGPROXY_KEY'),
    ],

];
```

And finally, a little bit of dependency injection:

`app/Providers/AppServiceProvider.php`:

```php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Imgproxy\UrlBuilder;
use Illuminate\Foundation\Application;

class AppServiceProvider extends ServiceProvider
{

    public function boot()
    {
        $this->app->bind(UrlBuilder::class, function (Application $app) {
            return new UrlBuilder(
                config('services.imgproxy.url'),
                config('services.imgproxy.key'),
                config('services.imgproxy.salt')
            );
        });
    }
}
```

## Middleware

The middleware is relatively simple.

```php {linenos=true,hl_lines=[50,51]}
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Imgproxy\UrlBuilder;
use PHPHtmlParser\Dom;
use Throwable;

class ImgproxyCmsContent
{
    /**
     * @param Request $request
     * @param Closure $next
     * @return Response
     */
    public function handle($request, Closure $next)
    {
```

You can add `?no_imgproxy` to url to skip the middleware for testing, etc.

```php {linenos=true,linenostart=23 }
        if ($request->has('no_imgproxy')) {
            return $next($request);
        }
```

Get the response content and load it into the DOM parser.

```php {linenos=true,linenostart=26 }
        /** @var Response $response */
        $response = $next($request);

        $dom = new Dom();
        try {
            $dom->loadStr($response->getContent());
```

For each `img` in the DOM, don't change `svg` and only rewrite images which are hosted on our site, i.e. in `public`; or hosted on our bucket.

`imgproxy` can be configured to host s3 content directly, but out of scope here, and serving public files is advantageous in this scenario.

```php {linenos=true,linenostart=32 }
            collect($dom->find('img'))
                ->reject(function (Dom\Node\HtmlNode $node) {
                    return Str::of($node->getAttribute('src'))
                        ->endsWith('.svg');
                })
                ->filter(function (Dom\Node\HtmlNode $node) {
                    $src = Str::of($node->getAttribute('src'));

                    return $src->startsWith(config('app.url'))
                        || $src->startsWith(Storage::disk('s3')->url('.'));
                })
                ->each(function (Dom\Node\HtmlNode $node) {
                    $node->setAttribute(
                        'src',
                        app(UrlBuilder::class)
                            ->build(
                                $node->getAttribute('src'),
```

Since this middleware is only applied to one section of the site which has a known max-width.

* Line 49: width - 896px, i.e. tailwind `max-w-4xl`; we constrain all images to this width
* Line 50: height - 0px, i.e. do not resize to a fixed height; aspect ratio will be respected

```php {linenos=true,linenostart=49,hl_lines=[1,2] }
                                896,
                                0
                            )
                            ->useAdvancedMode()
                            ->toString()
                    );
                });

            return $response->setContent((string) $dom);
        } catch (Throwable $e) {
            return $response;
        }
    }
}
```

You can see the middleware [gist](https://gist.github.com/alistaircol/e6f2f3cadc15400026048c8e8ff02a4f).
