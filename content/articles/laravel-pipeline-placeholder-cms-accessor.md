---
title: "Laravel pipeline to replace CMS content placeholders with values"
author: "Ally"
summary: "Use Laravel pipelines to replace arbitrary CMS placeholders with computed values using a model's accessor"
publishDate: 2022-08-25T13:13:51+0100
tags: ['laravel','pipeline']
---

We have a CMS which will generate content based on a couple of attributes (region, date). The template (containing placeholders) for the system to calculate, is determined by one of these attributes.

Each of these templates consist of a few sections.

* Overview
* Changes in data (relative and absolute) over last month
  * showing areas of the region with the largest increases
  * showing areas of the region with the largest decreases
* Changes in data (relative and absolute) over last year
  * showing areas of the region with the largest increases
  * showing areas of the region with the largest decreases

The raw template will be stored as part of the model (say `content`), and we can't replace this content with the placeholders replaced with their semantic values at creation, as this would mean editing the post will take the values at the time, when the values could change later.

You could:

* Listen for model events and update another attribute on the model the result of running the `content` through the placeholder replacement logic
* Listen for model events and place the result of running the `content` through the placeholder replacement logic in a cache, and use a model accessor to retrieve the value

## Why Pipelines

Simply put, you could get away with just using something like this for a small example:

```php
return Str::of($model->content)
    ->replace('[foo]', $foo)
    ->replace('[bar]', $bar);
```

But when there are multiple sections (with multiple placeholders) making some potentially non-trivial queries/transformations, this gets out of hand very quickly.

The templates I am working with have 120+ placeholders.

## Pipelines

A lesser documented component of the framework is [`Pipeline`](https://jeffochoa.me/understanding-laravel-pipelines)s.

These are ideal for our use case because as mentioned above, the templates contain a few sections, so making a pipeline step for each section is much more manageable.

## Template

Prior to creating the `Article`, I use the `region` and `date` from the request to determine which template is to be used.

The template is then set to `$article->content`.

## Pipeline Container

I make a DTO to pass into the pipeline, since it can bundle a few different objects together, e.g.:

* `Article $article`: the model that has been created, the `content` attribute contains the raw template with placeholders
* `string $region`: attribute (from the model) to get placeholder replacement values
* `CarbonImmutable $date`: attribute (from the model) to get placeholder replacement values
* `Stringable $output`: the output of the `$article->content` transformation
* `StatsCollector $stats`: contains various queries/transformations to replace the placeholders of `$output`

This container will have some getters/setters/helpers available to it too, there's nothing really worth noting, however.

## `Pipeline`

I construct the above DTO and pass this into the pipeline.

```php
use Illuminate\Pipeline\Pipeline;
use App\Article\ArticlePipelineContainer;

// implementation detail for this is irrelevant
$container = ArticlePipelineContainer::get();

return app(Pipeline::class)
    ->send($container)
    ->through([
        // TODO: pipes to transform $container->output
    ])
    ->then(function (ArticlePipelineContainer $container): string {
        return (string) $container->getOutput();
    })
```

## The `Pipe` interface

Each `Pipe` in the `Pipeline` will need to follow the following interface (obviously this can be changed):

```php
<?php

namespace App\Article\Pipe;

use Closure;
use App\Article\ArticlePipelineContainer;

interface ArticlePipe
{
    public function handle(ArticlePipelineContainer $container, Closure $next);
}
```

## My First Pipe

The transformation pipes will look something like this:

```php
<?php

namespace App\Article\Pipe;

use Closure;
use App\Article\Pipe\ArticlePipe;
use App\Article\ArticlePipelineContainer;

class ReplacePlaceholdersForSummary implements ArticlePipe
{
    public function handle(ArticlePipelineContainer $container, Closure $next)
    {
        $container->setOutput(
            $container->getOutput()
                ->replace(
                    '[REGION_MONTH_MAX_CHANGE]',
                    $container->getStats()->getRegionMonthMaxChange()
                )
                ->replace(
                    '[REGION_MONTH_MIN_CHANGE]',
                    $container->getStats()->getRegionMonthMinChange()
                )
        );
        
        // a few more transformations...
        
        // remember to always call the next pipe
        return $next($container);
    }
}
```

Add the pipe to your pipeline's `through`, it could end up looking like this:

```php
use Illuminate\Pipeline\Pipeline;
use App\Article\ArticlePipelineContainer;
use App\Article\Pipe\ReplacePlaceholdersForSummary;

// implementation detail for this is irrelevant
$container = ArticlePipelineContainer::get();

return app(Pipeline::class)
    ->send($container)
    ->through([
        ReplacePlaceholdersForSummary::class,
        ReplacePlaceholdersForAbsoluteChangeMonthAscending::class,
        ReplacePlaceholdersForAbsoluteChangeMonthDescending::class,
        ReplacePlaceholdersForRelativeChangeMonthAscending::class,
        ReplacePlaceholdersForRelativeChangeMonthDescending::class,
        ReplacePlaceholdersForAbsoluteChangeYearAscending::class,
        ReplacePlaceholdersForAbsoluteChangeYearDescending::class,
        ReplacePlaceholdersForRelativeChangeYearAscending::class,
        ReplacePlaceholdersForRelativeChangeYearDescending::class,
    ])
    ->then(function (ArticlePipelineContainer $container): string {
        return (string) $container->getOutput();
    })
```

Instead of an absolute monstrosity. Thank you, pipeline!
