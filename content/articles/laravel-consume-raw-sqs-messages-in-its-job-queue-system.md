---
title: "Consume raw SQS messages from another application with Laravel's queue"
author: "Ally"
summary: "Easily consume arbitrary raw AWS SQS messages by another application in your Laravel application's queue with a `Job` and `queue` configuration."
publishDate: 2022-08-27T13:37:44+0100
tags: ['laravel','aws','sqs']
---

An alternative method to webhooks might be pushing an event/message onto an AWS SQS queue and having any consumer deal with it however they want.

Unfortunately the other application might not use Laravel, or, if it does, the job name might not be compatible with your project.

I will outline with the use `terraform` to setup a SQS queue, and provide some commands to push raw messages, and the few steps required to set up the queue, and a job to process messages in Laravel.

![process](/img/articles/laravel-consume-raw-sqs-messages/terminal.png)

## AWS

We just need to create a simple queue, (not FIFO) and I use the default settings.

The next steps are to allow us to create messages through the cli, and optionally, create the queue using `terraform`.

Create a profile and set the config and credentials:

```bash
aws --profile=ally-api-webhooks configure
```

When enqueueing a message (or anything else, for that matter) with [`awscli`](https://aws.amazon.com/cli/) it closes out to a pager (`less` by default) which is super annoying, so the following command will disable it (alternatively you could use an environment variable `AWS_PAGER`).

```bash
aws --profile=ally-api-webhooks configure set cli_pager ''
```

## Terraform (optional)

The terraform script is simple, since SQS is relatively simple.

`main.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  profile                  = "ally-api-webhooks"
  region                   = "eu-west-2"
  shared_config_files      = [pathexpand("~/.aws/config")]
  shared_credentials_files = [pathexpand("~/.aws/credentials")]
}
```

`resources.tf`:

```hcl
resource "aws_sqs_queue" "webhook_queue" {
  name = "webhook_queue"
}

resource "aws_sqs_queue_policy" "webhook_queue_policy" {
  queue_url = aws_sqs_queue.webhook_queue.id

  policy = <<POLICY
{
  "Version": "2008-10-17",
  "Id": "webhook_queue_policy",
  "Statement": [
    {
      "Sid": "webhook_queue",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.account_id}"
      },
      "Action": [
        "SQS:*"
      ],
      "Resource": "arn:aws:sqs:eu-west-2:${data.aws_caller_identity.current.account_id}:"
    }
  ]
}
POLICY
}

```

`data.tf`:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
```

`output.tf`:

```hcl
output "queue_url" {
  value = aws_sqs_queue.webhook_queue.url
}

output "region" {
  value = data.aws_region.current.name
}
```

The core commands for `terraform` are:

```bash
terraform init
terraform fmt
terraform plan
terraform apply
```

This might take a minute, arguably quicker to create through the web UI.

## Project (optional)

This is for example purposes, so I create a fresh install.

```bash
docker run \
    --rm \
    --tty \
    --interactive \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd)/src:/app" \
    --volume="${COMPOSER_HOME:-$HOME/.composer}:/tmp" \
    --workdir=/app \
    thecodingmachine/php:7.4-v4-cli \
    composer create-project laravel/laravel=^8 src
```

Then to get a shell in the container:

```bash
docker run \
    --rm \
    --tty \
    --interactive \
    --user=$(id -u):$(id -g) \
    --volume="$(pwd)/src:/app" \
    --volume="${COMPOSER_HOME:-$HOME/.composer}:/tmp" \
    --workdir=/app \
    thecodingmachine/php:7.4-v4-cli \
    bash
```

## Driver

I use [`primitivesense/laravel-raw-sqs-connector`](https://packagist.org/packages/primitivesense/laravel-raw-sqs-connector) to interpret arbitrary SQS messages to be handled by a `Job` in Laravel world.

```bash
composer require dusterio/laravel-plain-sqs
```

After install, add their service provider into your `providers` in `config/app.php`:

```php
<?php

return [
    'providers' => [
        /*
         * Package Service Providers...
         */
        \PrimitiveSense\LaravelRawSqsConnector\RawSqsServiceProvider::class,
    ],
];
```

## Queue

Duplicate the `sqs` connection in `config/queue.php`, renaming it to `sqs-plain`.

Change the `driver` from `sqs` to `raw-sqs` - this new driver is from the package.

`config/queue.php`:

```php
<?php

return [
    'connections' => [
        'sqs-plain' => [
            // custom driver from the service provider
            'driver' => 'raw-sqs',
            'key'    => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'prefix' => env('SQS_PREFIX', 'https://sqs.us-east-1.amazonaws.com/your-account-id'),
            'queue'  => env('SQS_QUEUE', 'default'),
            'suffix' => env('SQS_SUFFIX'),
            'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
        ],
    ],
];
```

## Job

Create a new job to handle the SQS messages, i.e. `php artisan make:job ProcessWebhook`.

Make the following changes:

`app/Jobs/ProcessWebhook.php`:

```diff
 <?php
 
 namespace App\Jobs;
 
-use Illuminate\Bus\Queueable;
-use Illuminate\Contracts\Queue\ShouldQueue;
-use Illuminate\Foundation\Bus\Dispatchable;
-use Illuminate\Queue\InteractsWithQueue;
-use Illuminate\Queue\SerializesModels;
+use PrimitiveSense\LaravelRawSqsConnector\RawSqsJob;
 
-class ProcessWebhook implements ShouldQueue
+class ProcessWebhook extends RawSqsJob
 {
-    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
 
     public function handle()
     {
+          // TODO: handle the job, use $this->getData() to get SQS message contents
     }
 }
```

Finally, set `job_class` to `\App\Jobs\ProcessWebhook::class` in your `sqs-plain` queue connection in `config/queue.php`, i.e.:

```php {hl_lines=[8]}
<?php

return [
    'connections' => [
        'sqs-plain' => [
            // custom driver from the service provider
            'driver'    => 'raw-sqs',
            'job_class' => \App\Jobs\ProcessWebhook::class,
            'key'       => env('AWS_ACCESS_KEY_ID'),
            'secret'    => env('AWS_SECRET_ACCESS_KEY'),
            'prefix'    => env('SQS_PREFIX', 'https://sqs.us-east-1.amazonaws.com/your-account-id'),
            'queue'     => env('SQS_QUEUE', 'default'),
            'suffix'    => env('SQS_SUFFIX'),
            'region'    => env('AWS_DEFAULT_REGION', 'us-east-1'),
        ],
    ],
];
```

You should be good to consume messages now.

## Producer

Since the scenario is to process an arbitrary SQS payload with a `Job`, we will use [`aws sqs send-message`](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/sqs/send-message.html) to enqueue a 'job'.

```bash
cat <<EOF | aws \
  --profile=ally-api-webhooks \
  sqs \
  send-message \
  --queue-url=$(terraform output -raw queue_url) \
  --message-body file:///dev/stdin
```

```json
{
    "request_headers": [],
    "request_body": {
        "from": "$(hostname)",
        "at": "$(date)"
    }
}
```

```bash
EOF
```

## Consumer

The last step is to run the queue.

Monitor/verify configuration:

```bash
php artisan queue:monitor sqs-plain:webhook_queue
```

Process the message:

```bash
php artisan queue:work --once --queue=webhook_queue sqs-plain
```
