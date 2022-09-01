---
title: "Send WhatsApp messages in Laravel"
author: "Ally"
summary: "Send a message template containing emoji from Twilio in Laravel"
publishDate: 2022-08-30T16:58:02+0100
tags: ['laravel','whatsapp','twilio']
cover: https://ac93.uk/img/unsplash/dimitri-karastelev-ynJaWgrwSlM-unsplash.jpg
---

Imagine you need to send (on some schedule) a notification, of, say, a users' portfolio value, then a WhatsApp message might be ideal.

I used the following packages to help:

* [`twilio/sdk`](https://packagist.org/packages/twilio/sdk)
* [`elvanto/litemoji`](https://packagist.org/packages/elvanto/litemoji)
* [`giggsey/libphonenumber-for-php`](https://packagist.org/packages/giggsey/libphonenumber-for-php)

## Validation

I use [`giggsey/libphonenumber-for-php`](https://packagist.org/packages/giggsey/libphonenumber-for-php) for validation of a given number.

First, some things for DI:

`app/Providers/AppServiceProvider.php`:

```php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use libphonenumber\PhoneNumberUtil;

class AppServiceProvider extends ServiceProvider
{
    public function boot()
    {
        $this->app->bind(PhoneNumberUtil::class, function () {
            return PhoneNumberUtil::getInstance();
        });
    }
}
```

I use the following accessors in the model, so we can use it in a validation rule, or in `Collection`'s `reject`/`filter` in future scenarios.

`app/Models/Portfolio.php`:

```php
    public function getHasValidPhoneNumberAttribute(): bool
    {
        if (blank($this->phone)) {
            return false;
        }

        $helper = app(PhoneNumberUtil::class);

        try {
```

You might want to exchange the `GB` with a relevant ISO 3316-2 country code if the number is not written in [E.164](https://www.twilio.com/docs/glossary/what-e164) format.  

```php
            $phone = $helper->parse($this->phone, 'GB');

            return $helper->isValidNumber($phone);
        } catch (Throwable $e) {
            return false;
        }
    }

    public function getWhatsappPhoneNumberAttribute(): ?string
    {
        if (!$this->getHasValidPhoneNumberAttribute()) {
            return null;
        }

        $helper = app(PhoneNumberUtil::class);

        try {
            $phone = $helper->parse($this->phone, 'GB');

            return (string) Str::of($helper->format($phone, PhoneNumberFormat::E164))
```

When sending API requests to twilio for sending a WhatsApp message, the number requires this `whatsapp:` prefix.

```php
                ->prepend('whatsapp:');
        } catch (Throwable $e) {
            return null;
        }
    }
```


## Permission

I use [`spatie/laravel-permissions`](https://packagist.org/packages/spatie/laravel-permission) at the user level to determine whether they have opted-in to receive WhatsApp messages.

It's as simple as:

```php
$user->can('receive whatsapp messages');
```

## Templating

Templating was a little weird to me at first.

You specify a template on twilio something like this:

```text
📊 {{1}} portfolio has {{2}} in value. It is now worth: {{3}}
```

However, unlike most other APIs where you specify the template ID and then the template model/data like:

```php
[
    1 => 'Crypto',
    2 => $direction < 1 ? 'decreased' : 'increased',
    3 => '£' . number_format($value, 2),
]
```

You however need to construct the template yourself, and then send that as the payload. This gets a little awkward when using emoji (some editors might strip it out, achieving correct spacing might be difficult, etc), so I use [`elvanto/litemoji`](https://packagist.org/packages/elvanto/litemoji) to make that easier.

```php
use Illuminate\Support\Str;
use LitEmoji\LitEmoji;

$template = Str::of('? ? portfolio has ? in value. It is now worth: ?');

$message = $template->replaceArray([
    LitEmoji::shortcodeToUnicode(':bar_chart:'),
    'Crypto',
    'decreased',
    '£187.51'
]);
```

So the `body` in the payload you will send will be something like this:

```text
📊 Crypto portfolio has decreased in value. It is now worth: £187.51
```

## Dispatching

I will dispatch a job for each message, the job will be fairly simple:

`app/Jobs/SendWhatsAppMessage.php`:

```php
<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Queue\InteractsWithQueue;
use Twilio\Rest\Client;

class SendWhatsAppMessage implements ShouldQueue
{
    use InteractsWithQueue;
    use Queueable;

    public string $from;
    public string $to;
    public string $message;

    public function __construct(string $from, string $to, string $message)
    {
        $this->from = $from;
        $this->to = $to;
        $this->message = $message;
    }

    public function handle()
    {
```

This `Client` dependency injection will be left to the user, basically `ssid` and `token` passed into `Twilio\Rest\Client` constructor.

```php
        $twilio = app(Client::class);

        $twilio->messages->create($this->to, [
            'from' => $this->from,
            'body' => $this->message,
        ]);
    }
}
```

## Command

There is a command to run on a schedule (the command signature or how to add on the schedule are not important).

You might want to consider some options/arguments to:

* change the chunk size (`--chunk-size=100`)
* search only a subset if certain conditionals are used (`--portfolios=comma,separated,list`)
* dump as json for debugging, or not queueing the jobs (`--dry-run`)
* send message to a debug number (i.e. not to real users) (`--blackhole`)

Its `handle` might look something like this, using `chunkById` to get some better performance.

```php
Portfilio::query()
    ->whereHas('user', fn (Builder $query) => $query->whereNotNull('phone'))
    ->chunkById(100, function (Collection $portfolios) {
        $portfolios
            ->filter(fn (Portfolio $portfolio) => $portfolio->user->can('receive whatsapp messages'))
            ->filter(fn (Portfolio $portfolio) => $portfolio->user->has_valid_phone_number)
            ->map(fn (Portfolio $portfolio) => PortfolioUpdateDto::fromPortfolio($portfolio))
            ->each(function (PortfolioUpdateDto $dto) {
                dispatch(new SendWhatsAppMessage($dto->from, $dto->to, $dto->message));
            });
    });
```
