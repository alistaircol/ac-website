---
title: "Basic Cognito user pool with login/logout integration in Laravel, with users/system clients"
author: "Ally"
summary: "A relatively basic Laravel integration with an Amazon Cognito user pool with two clients. The first client for web users will be used to initiate (from Laravel) login/logout on Cognito's hosted UI with email/password. The second client will be for system users, which will generate tokens with email/password through API instead of hosted UI. Finally, a simple console command to decode/verify web and system users' JTWs from the user pool's JWKS."
publishDate: 2022-09-24T09:09:32+01:00
tags: ['laravel','cognito','terraform']
draft: false
---

GitHub repo [here](https://github.com/alistaircol/cognito-laravel-integration)

![Hosted Login](/img/articles/laravel-cognito/login.png)

## Scenario

Imagine we are setting up a MMORPG, we will want two clients:

* players who will authenticate using web hosted UI with email/password
* system users who will authenticate using API, they will respond to webhooks/queues/schedulers etc.

## Pre-requisites

* Install [`terraform`](https://www.terraform.io/downloads)
* Install [`aws-cli`](https://aws.amazon.com/cli/)

## IAM

* Create a new user (e.g. `dafed`) with programmatic access, or assign the `AmazonCognitoPowerUser` policy to an existing user.
* Create a new AWS profile using `aws-cli` for this new user on your host device.

Profile is optional, but recommended.

```bash
aws --profile=dafed configure
```

## Terraform Input Variables

Before setting up the provider, we first need to set up some [input variables](https://www.terraform.io/language/values/variables).

`variables.tf`:

```hcl {linenos=true}
# I set up `aws configure` with this profile
variable "aws_profile" {
  type    = string
  default = "dafed"
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

# The subdomain of cognito IDP for the hosted UI
variable "cognito_user_pool_domain" {
  type    = string
  default = "dafedteam"
}

# The name of our user pool
variable "cognito_user_pool_name" {
  type    = string
  default = "players"
}

# List of users in our pool
variable "cognito_user_pool_members" {
  type = list(object({
    email    = string
    password = string
  }))
}
```

Below are lists of the URLs for the web users client for redirecting after login/logout.

I have just one URL, but you may want to add multiple for each environment, e.g. dev/staging/prod, etc.

```hcl {linenos=true, linenostart=32}
# List of URLs that can be redirected to after login
# from the hosted UI
variable "web_callback_urls" {
  type = list(string)
  default = [
    "https://t3.dafedteam.test/login-success"
  ]
}

# List of URLs that can be redirected to after logout
# from the hosted UI
variable "web_logout_urls" {
  type = list(string)
  default = [
    "https://t3.dafedteam.test/logout-success"
  ]
}
```

There are some values you may wish to override and some that need set from the above `variables.tf` file.

The best way to do this is with a `terraform.tfvars` file. This is picked up automatically by `terraform`, you can specify another file with `-var-file`.

`terraform.tfvars`:

```hcl
cognito_user_pool_members = [
  {
    email    = "a@org.com"
    password = "9I7FrRkjnVjkKU71"
  },
  {
    email    = "b@org.com"
    password = "9I7FrRkjnVjkKU72"
  }
]
```

## Terraform Provider

Set up the main provider with some AWS variables, and let it use the credentials set up from the profile earlier.

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
  profile                  = var.aws_profile
  region                   = var.aws_region
  shared_config_files      = [pathexpand("~/.aws/config")]
  shared_credentials_files = [pathexpand("~/.aws/credentials")]
}
```

## Cognito User Pool

Set up the user pool with a subdomain which is required for the hosted UI, and a customisation to change the logo.

In my scenario, I am developing an MMORPG, so registration is closed, therefore users can only be created from Cognito.

`resources.tf`:

```hcl {linenos=true}
resource "aws_cognito_user_pool" "dafed" {
  name = var.cognito_user_pool_name

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # https://stackoverflow.com/a/73434724/5873008
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_domain" "dafed" {
  domain       = var.cognito_user_pool_domain
  user_pool_id = aws_cognito_user_pool.dafed.id
}

resource "aws_cognito_user_pool_ui_customization" "example" {
  user_pool_id = aws_cognito_user_pool_domain.dafed.user_pool_id
  image_file   = filebase64("resources/logo.png")
}
```

## Cognito User Pool: Client for Users

Set up a client for users to authenticate using the hosted UI.

`resources.tf`:

```hcl {linenos=true, linenostart=38}
resource "aws_cognito_user_pool_client" "web" {
  name         = "web"
  user_pool_id = aws_cognito_user_pool.dafed.id

  generate_secret         = true
  enable_token_revocation = true
  access_token_validity   = 60
  id_token_validity       = 60
  refresh_token_validity  = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = [
    "code",
    "implicit"
  ]
  allowed_oauth_scopes = [
    "email",
    "openid",
    "phone",
    "profile"
  ]
  supported_identity_providers = [
    "COGNITO"
  ]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  callback_urls = var.web_callback_urls
  logout_urls   = var.web_logout_urls
}
```

## Cognito User Pool: Client for Systems

Set up a client for users to authenticate as admin using the API.

`resources.tf`:

```hcl {linenos=true, linenostart=77}
resource "aws_cognito_user_pool_client" "system" {
  name         = "system"
  user_pool_id = aws_cognito_user_pool.dafed.id

  generate_secret         = true
  enable_token_revocation = true
  access_token_validity   = 60
  id_token_validity       = 60
  refresh_token_validity  = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  supported_identity_providers = [
    "COGNITO"
  ]

  explicit_auth_flows = [
    "ADMIN_NO_SRP_AUTH"
  ]
}
```

![Clients](/img/articles/laravel-cognito/clients.png)

## Cognito User Pool: Users

We will add a list of users to the pool.

`resources.tf`:

```hcl {linenos=true, linenostart=101}
resource "aws_cognito_user" "players" {
  count = length(var.cognito_user_pool_members)

  user_pool_id = aws_cognito_user_pool.dafed.id
  username     = var.cognito_user_pool_members[count.index].email
  password     = var.cognito_user_pool_members[count.index].password

  attributes = {
    email          = var.cognito_user_pool_members[count.index].email
    email_verified = true
  }
}
```

![Users](/img/articles/laravel-cognito/users.png)

## Terraform Output Variables

Some handy output variables for:

* one off download files
* debugging prior to working on an integration to check configuration
* credentials required to be available in an integration 

`outputs.tf`:

The `cognito_json_web_key_set` is needed to verify tokens, this is only needed to be downloaded once.

```hcl {linenos=true}
output "cognito_json_web_key_set" {
  value = "https://${aws_cognito_user_pool.dafed.endpoint}/.well-known/jwks.json"
}
```

The `login_uri` and `logout_uri` are handy for testing prior to making an integration.

```hcl {linenos=true linenostart=4}
output "login_uri" {
  value = "https://${aws_cognito_user_pool_domain.dafed.domain}.auth.${var.aws_region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.web.id}&response_type=code&redirect_uri=${element(tolist(aws_cognito_user_pool_client.web.callback_urls), 0)}"
}

output "logout_uri" {
  value = "https://${aws_cognito_user_pool_domain.dafed.domain}.auth.${var.aws_region}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.web.id}&logout_uri=${element(tolist(aws_cognito_user_pool_client.web.logout_urls), 0)}"
}
```

The rest of these outputs could be added as environment variables for the integration.

```hcl {linenos=true linenostart=12}
output "AWS_COGNITO_IDP_URI" {
  value = "https://${aws_cognito_user_pool_domain.dafed.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "AWS_COGNITO_USER_POOL_ID" {
  value = aws_cognito_user_pool.dafed.id
}

output "AWS_COGNITO_USER_POOL_WEB_CLIENT_ID" {
  value     = aws_cognito_user_pool_client.web.id
}

output "AWS_COGNITO_USER_POOL_WEB_CLIENT_SECRET" {
  value     = aws_cognito_user_pool_client.web.client_secret
  sensitive = true
}

output "AWS_COGNITO_USER_POOL_API_CLIENT_ID" {
  value     = aws_cognito_user_pool_client.system.id
}

output "AWS_COGNITO_USER_POOL_API_CLIENT_SECRET" {
  value     = aws_cognito_user_pool_client.system.client_secret
  sensitive = true
}

output "AWS_DEFAULT_REGION" {
  value = var.aws_region
}
```

You will need `aws_access_key_id` and `aws_secret_access_key` for generating system tokens with credentials through the API with [`AdminInitiateAuth`](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_AdminInitiateAuth.html)

There are a couple of methods for the getting the `aws_access_key_id`.

You can add `aws_caller_identity` data provider, e.g.:

`data.tf`:

```hcl {linenos=true}
data "aws_caller_identity" "current" {}
```

`outputs.tf`:

```hcl {linenos=true, linenostart=42}
output "AWS_ACCESS_KEY_ID" {
  value = data.aws_caller_identity.current.user_id
}
```

Alternatively:

```bash
aws --profile=${var.aws_profile} configure get aws_access_key_id
```

There's no easy way within `terraform` to get the AWS secret access key. The easiest way would be like this:

```bash
aws --profile=${var.aws_profile} configure get aws_secret_access_key
```

Finally, get `terraform` to create the infrastructure.

```bash
terraform init
terraform fmt
terraform plan
terraform apply
```

## Integration Pre-requisites

I will basically just use Laravel's [`Http`](https://laravel.com/docs/9.x/http-client) client, but I will also use:

* [`spatie/url`](https://github.com/spatie/url) to build login/logout initiation URLs
* [`firebase/php-jwt`](https://github.com/firebase/php-jwt) to verify/decode JWT from cognito
* [`aws/aws-sdk-php`](https://github.com/aws/aws-sdk-php) to generate tokens via [`AdminInitiateAuth`](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_AdminInitiateAuth.html) with email/password without using hosted UI. Note, this needs AWS access key and secret access key.

{{<accordion title="Install dependencies with `composer`">}}
```bash
composer require spatie/url
composer require firebase/php-jwt
composer require aws/aws-sdk-php
```
{{</accordion>}}

## Integration Config

Using the `terraform output`s from earlier, add the following environment variables:

```env
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=eu-west-2

AWS_COGNITO_IDP_URI=
AWS_COGNITO_USER_POOL_ID=
AWS_COGNITO_USER_POOL_WEB_CLIENT_ID=
AWS_COGNITO_USER_POOL_WEB_CLIENT_SECRET=
AWS_COGNITO_USER_POOL_API_CLIENT_ID=
AWS_COGNITO_USER_POOL_API_CLIENT_SECRET=
```

For the admin user (just pick one from the user pool):

```env
DAFED_ADMIN_USERNAME=
DAFED_ADMIN_PASSWORD=
```

I add these to `config/auth.php`:

```php
<?php

return [
    
    //
    
    'cognito' => [
        'aws_access_key' => env('AWS_ACCESS_KEY_ID'),
        'aws_secret_access_key' => env('AWS_SECRET_ACCESS_KEY'),
    
        'idp_uri' => env('AWS_COGNITO_IDP_URI'),
        'user_pool_id' => env('AWS_COGNITO_USER_POOL_ID'),
        
        'clients' => [
            'web' => [
                'client_id' => env('AWS_COGNITO_USER_POOL_WEB_CLIENT_ID'),
                'client_secret' => env('AWS_COGNITO_USER_POOL_WEB_CLIENT_SECRET'),
            ],
            'system' => [
                'client_id' => env('AWS_COGNITO_USER_POOL_API_CLIENT_ID'),
                'client_secret' => env('AWS_COGNITO_USER_POOL_API_CLIENT_SECRET'),
                
                'admin' => [
                    'user' => env('DAFED_ADMIN_USERNAME'),
                    'pass' => env('DAFED_ADMIN_PASSWORD'),
                ],
            ],
        ],
    ],
];
```

Using valet to host the integration:

```bash
composer global require laravel/valet
export PATH="$PATH:$(realpath ~/.composer/vendor/bin)"
valet install
valet link --secure t3.dafedteam
```

## Integration Migration

For simplicity, I have a migration to store the tokens from Cognito on the `users` table:

* `cognito_access_token`
* `cognito_id_token`
* `cognito_refresh_token`
* `cognito_access_token_expires_at`

{{<accordion title="Migration">}}
```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('cognito_access_token')->nullable();
            $table->text('cognito_id_token')->nullable();
            $table->text('cognito_refresh_token')->nullable();
            $table->dateTime('cognito_access_token_expires_at')->nullable();
        });
    }

    public function down()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'cognito_access_token',
                'cognito_id_token',
                'cognito_refresh_token',
                'cognito_access_token_expires_at',
            ]);
        });
    }
};
```
{{</accordion>}}

## Integration Model

I have created a new trait that the `User` model will use, this is to reduce clutter in the model if you decide to no longer use Cognito.

`app/Traits/HasCognitoTokens.php`:

```php
<?php

namespace App\Traits;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Client\Response;

/**
 * @method Model mergeFillable(array $fillable)
 * @method Model mergeCasts(array $casts)
 * @method Model setAttribute(string $key, mixed $value)
 * @method mixed getAttribute(string $key)
 * @method Model save(array $options = [])
 */
trait HasCognitoTokens
{
    protected function getCognitoTokenAttributeNames(): array
    {
        return [
            'cognito_access_token',
            'cognito_id_token',
            'cognito_refresh_token',
            'cognito_access_token_expires_at',
        ];
    }

    /**
     * @see \Illuminate\Database\Eloquent\Model::bootTraits()
     * @see \Illuminate\Database\Eloquent\Concerns\GuardsAttributes::mergeFillable()
     * @return void
     */
    protected function initializeHasCognitoTokens(): void
    {
        $this->mergeFillable($this->getCognitoTokenAttributeNames());
        $this->mergeCasts([
            'cognito_access_token_expires_at' => 'datetime',
        ]);
    }

    public function resetCognitoTokens(): void
    {
        foreach ($this->getCognitoTokenAttributeNames() as $attribute) {
            $this->setAttribute($attribute, null);
        }

        $this->save();
    }

    public function setCognitoTokensFromResponse(Response $response): void
    {
        $this->setAttribute('cognito_access_token', $response->json('access_token'));
        $this->setAttribute('cognito_id_token', $response->json('id_token'));
        $this->setAttribute('cognito_refresh_token', $response->json('refresh_token'));
        $this->setAttribute('cognito_access_token_expires_at', now()->addSeconds($response->json('expires_in', 0)));
        $this->save();
    }

    public function getJwtAttribute(): ?string
    {
        return $this->getAttribute('cognito_id_token');
    }
}
```

## Integration Routes

For the basic integration I use the following routes:

{{<accordion title="`artisan` commands to generate the controllers mentioned in the `routes/web.php`">}}
```bash
php artisan make:controller -i IndexController
php artisan make:controller -i LoginController
php artisan make:controller -i LoginSuccessController
php artisan make:controller -i LogoutController
php artisan make:controller -i LogoutSuccessController
```
{{</accordion>}}

`routes/web.php`:

```php {linenos=true}
Route::get('/', \App\Http\Controllers\IndexController::class)->name('index');
```

The `index` route is the landing page and the content differs using `@auth` and `@guest`, etc.

```php {linenos=true, linenostart=2}
Route::get('login', \App\Http\Controllers\LoginController::class)->name('login');
```

The `login` route will build URL for Cognito's hosted login page and redirect the user there.

```php {linenos=true, linenostart=3}
Route::any('login-success', \App\Http\Controllers\LoginSuccessController::class)->name('login.success');
```

If the user is successfully authenticated on Cognito hosted UI, they will be redirected back to `login.success`. This is the most complicated part of the integration and will go into more details later.

```php {linenos=true, linenostart=4}
Route::get('logout', \App\Http\Controllers\LogoutController::class)->name('logout');
```

The `logout` route is similar to the `login` one, it will build URL for Cognito's hosted logout page and redirect the user there.

```php {linenos=true, linenostart=5}
Route::any('logout-success', \App\Http\Controllers\LogoutSuccessController::class)->name('logout.success');
```

Like the `login.success`, the user is redirected back to this route after the hosted UI logout page has finished.

{{<accordion title="`routes/web.php`">}}
```php
Route::get('/', \App\Http\Controllers\IndexController::class)->name('index');
Route::get('login', \App\Http\Controllers\LoginController::class)->name('login');
Route::any('login-success', \App\Http\Controllers\LoginSuccessController::class)->name('login.success');
Route::get('logout', \App\Http\Controllers\LogoutController::class)->name('logout');
Route::any('logout-success', \App\Http\Controllers\LogoutSuccessController::class)->name('logout.success');
```
{{</accordion>}}

## Integration: Home & Dashboard

The 'main' page - the content differs using `@auth` and `@guest`, etc.

`app/Http/Controllers/IndexController.php`:

```php
<?php

namespace App\Http\Controllers;

class IndexController extends Controller
{
    public function __invoke()
    {
        return view('welcome');
    }
}
```

{{<accordion title="`resources/views/welcome.blade.php`">}}
```php
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <title>{{ config('app.name') }}</title>

    <!-- Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700&display=swap" rel="stylesheet">

    <!-- Styles -->
    <style>
        /*! normalize.css v8.0.1 | MIT License | github.com/necolas/normalize.css */html{line-height:1.15;-webkit-text-size-adjust:100%}body{margin:0}a{background-color:transparent}[hidden]{display:none}html{font-family:system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica Neue,Arial,Noto Sans,sans-serif,Apple Color Emoji,Segoe UI Emoji,Segoe UI Symbol,Noto Color Emoji;line-height:1.5}*,:after,:before{box-sizing:border-box;border:0 solid #e2e8f0}a{color:inherit;text-decoration:inherit}svg,video{display:block;vertical-align:middle}video{max-width:100%;height:auto}.bg-white{--bg-opacity:1;background-color:#fff;background-color:rgba(255,255,255,var(--bg-opacity))}.bg-gray-100{--bg-opacity:1;background-color:#f7fafc;background-color:rgba(247,250,252,var(--bg-opacity))}.border-gray-200{--border-opacity:1;border-color:#edf2f7;border-color:rgba(237,242,247,var(--border-opacity))}.border-t{border-top-width:1px}.flex{display:flex}.grid{display:grid}.hidden{display:none}.items-center{align-items:center}.justify-center{justify-content:center}.font-semibold{font-weight:600}.h-5{height:1.25rem}.h-8{height:2rem}.h-16{height:4rem}.text-sm{font-size:.875rem}.text-lg{font-size:1.125rem}.leading-7{line-height:1.75rem}.mx-auto{margin-left:auto;margin-right:auto}.ml-1{margin-left:.25rem}.mt-2{margin-top:.5rem}.mr-2{margin-right:.5rem}.ml-2{margin-left:.5rem}.mt-4{margin-top:1rem}.ml-4{margin-left:1rem}.mt-8{margin-top:2rem}.ml-12{margin-left:3rem}.-mt-px{margin-top:-1px}.max-w-6xl{max-width:72rem}.min-h-screen{min-height:100vh}.overflow-hidden{overflow:hidden}.p-6{padding:1.5rem}.py-4{padding-top:1rem;padding-bottom:1rem}.px-6{padding-left:1.5rem;padding-right:1.5rem}.pt-8{padding-top:2rem}.fixed{position:fixed}.relative{position:relative}.top-0{top:0}.right-0{right:0}.shadow{box-shadow:0 1px 3px 0 rgba(0,0,0,.1),0 1px 2px 0 rgba(0,0,0,.06)}.text-center{text-align:center}.text-gray-200{--text-opacity:1;color:#edf2f7;color:rgba(237,242,247,var(--text-opacity))}.text-gray-300{--text-opacity:1;color:#e2e8f0;color:rgba(226,232,240,var(--text-opacity))}.text-gray-400{--text-opacity:1;color:#cbd5e0;color:rgba(203,213,224,var(--text-opacity))}.text-gray-500{--text-opacity:1;color:#a0aec0;color:rgba(160,174,192,var(--text-opacity))}.text-gray-600{--text-opacity:1;color:#718096;color:rgba(113,128,150,var(--text-opacity))}.text-gray-700{--text-opacity:1;color:#4a5568;color:rgba(74,85,104,var(--text-opacity))}.text-gray-900{--text-opacity:1;color:#1a202c;color:rgba(26,32,44,var(--text-opacity))}.underline{text-decoration:underline}.antialiased{-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}.w-5{width:1.25rem}.w-8{width:2rem}.w-auto{width:auto}.grid-cols-1{grid-template-columns:repeat(1,minmax(0,1fr))}@media (min-width:640px){.sm\:rounded-lg{border-radius:.5rem}.sm\:block{display:block}.sm\:items-center{align-items:center}.sm\:justify-start{justify-content:flex-start}.sm\:justify-between{justify-content:space-between}.sm\:h-20{height:5rem}.sm\:ml-0{margin-left:0}.sm\:px-6{padding-left:1.5rem;padding-right:1.5rem}.sm\:pt-0{padding-top:0}.sm\:text-left{text-align:left}.sm\:text-right{text-align:right}}@media (min-width:768px){.md\:border-t-0{border-top-width:0}.md\:border-l{border-left-width:1px}.md\:grid-cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}}@media (min-width:1024px){.lg\:px-8{padding-left:2rem;padding-right:2rem}}@media (prefers-color-scheme:dark){.dark\:bg-gray-800{--bg-opacity:1;background-color:#2d3748;background-color:rgba(45,55,72,var(--bg-opacity))}.dark\:bg-gray-900{--bg-opacity:1;background-color:#1a202c;background-color:rgba(26,32,44,var(--bg-opacity))}.dark\:border-gray-700{--border-opacity:1;border-color:#4a5568;border-color:rgba(74,85,104,var(--border-opacity))}.dark\:text-white{--text-opacity:1;color:#fff;color:rgba(255,255,255,var(--text-opacity))}.dark\:text-gray-400{--text-opacity:1;color:#cbd5e0;color:rgba(203,213,224,var(--text-opacity))}.dark\:text-gray-500{--tw-text-opacity:1;color:#6b7280;color:rgba(107,114,128,var(--tw-text-opacity))}}
    </style>

    <style>
        body {
            font-family: 'Nunito', sans-serif;
        }
    </style>
</head>
<body class="antialiased">
<div class="relative flex items-top justify-center min-h-screen bg-gray-100 dark:bg-gray-900 sm:items-center py-4 sm:pt-0">
    @if (Route::has('login'))
        <div class="hidden fixed top-0 right-0 px-6 py-4 sm:block">
            @auth
                <a href="{{ route('index') }}" class="text-sm text-gray-700 dark:text-gray-500 underline">Home</a>
                <a href="{{ route('logout') }}" class="text-sm text-gray-700 dark:text-gray-500 underline">Logout</a>
            @else
                <a href="{{ route('login') }}" class="text-sm text-gray-700 dark:text-gray-500 underline">Log in</a>

                @if (Route::has('register'))
                    <a href="{{ route('register') }}" class="ml-4 text-sm text-gray-700 dark:text-gray-500 underline">Register</a>
                @endif
            @endauth
        </div>
    @endif

    <div class="max-w-6xl mx-auto sm:px-6 lg:px-8">
        <div class="flex justify-center pt-8 sm:justify-start sm:pt-0">
            <svg viewBox="0 0 651 192" fill="none" xmlns="http://www.w3.org/2000/svg" class="h-16 w-auto text-gray-700 sm:h-20">
                <g clip-path="url(#clip0)" fill="#EF3B2D">
                    <path d="M248.032 44.676h-16.466v100.23h47.394v-14.748h-30.928V44.676zM337.091 87.202c-2.101-3.341-5.083-5.965-8.949-7.875-3.865-1.909-7.756-2.864-11.669-2.864-5.062 0-9.69.931-13.89 2.792-4.201 1.861-7.804 4.417-10.811 7.661-3.007 3.246-5.347 6.993-7.016 11.239-1.672 4.249-2.506 8.713-2.506 13.389 0 4.774.834 9.26 2.506 13.459 1.669 4.202 4.009 7.925 7.016 11.169 3.007 3.246 6.609 5.799 10.811 7.66 4.199 1.861 8.828 2.792 13.89 2.792 3.913 0 7.804-.955 11.669-2.863 3.866-1.908 6.849-4.533 8.949-7.875v9.021h15.607V78.182h-15.607v9.02zm-1.431 32.503c-.955 2.578-2.291 4.821-4.009 6.73-1.719 1.91-3.795 3.437-6.229 4.582-2.435 1.146-5.133 1.718-8.091 1.718-2.96 0-5.633-.572-8.019-1.718-2.387-1.146-4.438-2.672-6.156-4.582-1.719-1.909-3.032-4.152-3.938-6.73-.909-2.577-1.36-5.298-1.36-8.161 0-2.864.451-5.585 1.36-8.162.905-2.577 2.219-4.819 3.938-6.729 1.718-1.908 3.77-3.437 6.156-4.582 2.386-1.146 5.059-1.718 8.019-1.718 2.958 0 5.656.572 8.091 1.718 2.434 1.146 4.51 2.674 6.229 4.582 1.718 1.91 3.054 4.152 4.009 6.729.953 2.577 1.432 5.298 1.432 8.162-.001 2.863-.479 5.584-1.432 8.161zM463.954 87.202c-2.101-3.341-5.083-5.965-8.949-7.875-3.865-1.909-7.756-2.864-11.669-2.864-5.062 0-9.69.931-13.89 2.792-4.201 1.861-7.804 4.417-10.811 7.661-3.007 3.246-5.347 6.993-7.016 11.239-1.672 4.249-2.506 8.713-2.506 13.389 0 4.774.834 9.26 2.506 13.459 1.669 4.202 4.009 7.925 7.016 11.169 3.007 3.246 6.609 5.799 10.811 7.66 4.199 1.861 8.828 2.792 13.89 2.792 3.913 0 7.804-.955 11.669-2.863 3.866-1.908 6.849-4.533 8.949-7.875v9.021h15.607V78.182h-15.607v9.02zm-1.432 32.503c-.955 2.578-2.291 4.821-4.009 6.73-1.719 1.91-3.795 3.437-6.229 4.582-2.435 1.146-5.133 1.718-8.091 1.718-2.96 0-5.633-.572-8.019-1.718-2.387-1.146-4.438-2.672-6.156-4.582-1.719-1.909-3.032-4.152-3.938-6.73-.909-2.577-1.36-5.298-1.36-8.161 0-2.864.451-5.585 1.36-8.162.905-2.577 2.219-4.819 3.938-6.729 1.718-1.908 3.77-3.437 6.156-4.582 2.386-1.146 5.059-1.718 8.019-1.718 2.958 0 5.656.572 8.091 1.718 2.434 1.146 4.51 2.674 6.229 4.582 1.718 1.91 3.054 4.152 4.009 6.729.953 2.577 1.432 5.298 1.432 8.162 0 2.863-.479 5.584-1.432 8.161zM650.772 44.676h-15.606v100.23h15.606V44.676zM365.013 144.906h15.607V93.538h26.776V78.182h-42.383v66.724zM542.133 78.182l-19.616 51.096-19.616-51.096h-15.808l25.617 66.724h19.614l25.617-66.724h-15.808zM591.98 76.466c-19.112 0-34.239 15.706-34.239 35.079 0 21.416 14.641 35.079 36.239 35.079 12.088 0 19.806-4.622 29.234-14.688l-10.544-8.158c-.006.008-7.958 10.449-19.832 10.449-13.802 0-19.612-11.127-19.612-16.884h51.777c2.72-22.043-11.772-40.877-33.023-40.877zm-18.713 29.28c.12-1.284 1.917-16.884 18.589-16.884 16.671 0 18.697 15.598 18.813 16.884h-37.402zM184.068 43.892c-.024-.088-.073-.165-.104-.25-.058-.157-.108-.316-.191-.46-.056-.097-.137-.176-.203-.265-.087-.117-.161-.242-.265-.345-.085-.086-.194-.148-.29-.223-.109-.085-.206-.182-.327-.252l-.002-.001-.002-.002-35.648-20.524a2.971 2.971 0 00-2.964 0l-35.647 20.522-.002.002-.002.001c-.121.07-.219.167-.327.252-.096.075-.205.138-.29.223-.103.103-.178.228-.265.345-.066.089-.147.169-.203.265-.083.144-.133.304-.191.46-.031.085-.08.162-.104.25-.067.249-.103.51-.103.776v38.979l-29.706 17.103V24.493a3 3 0 00-.103-.776c-.024-.088-.073-.165-.104-.25-.058-.157-.108-.316-.191-.46-.056-.097-.137-.176-.203-.265-.087-.117-.161-.242-.265-.345-.085-.086-.194-.148-.29-.223-.109-.085-.206-.182-.327-.252l-.002-.001-.002-.002L40.098 1.396a2.971 2.971 0 00-2.964 0L1.487 21.919l-.002.002-.002.001c-.121.07-.219.167-.327.252-.096.075-.205.138-.29.223-.103.103-.178.228-.265.345-.066.089-.147.169-.203.265-.083.144-.133.304-.191.46-.031.085-.08.162-.104.25-.067.249-.103.51-.103.776v122.09c0 1.063.568 2.044 1.489 2.575l71.293 41.045c.156.089.324.143.49.202.078.028.15.074.23.095a2.98 2.98 0 001.524 0c.069-.018.132-.059.2-.083.176-.061.354-.119.519-.214l71.293-41.045a2.971 2.971 0 001.489-2.575v-38.979l34.158-19.666a2.971 2.971 0 001.489-2.575V44.666a3.075 3.075 0 00-.106-.774zM74.255 143.167l-29.648-16.779 31.136-17.926.001-.001 34.164-19.669 29.674 17.084-21.772 12.428-43.555 24.863zm68.329-76.259v33.841l-12.475-7.182-17.231-9.92V49.806l12.475 7.182 17.231 9.92zm2.97-39.335l29.693 17.095-29.693 17.095-29.693-17.095 29.693-17.095zM54.06 114.089l-12.475 7.182V46.733l17.231-9.92 12.475-7.182v74.537l-17.231 9.921zM38.614 7.398l29.693 17.095-29.693 17.095L8.921 24.493 38.614 7.398zM5.938 29.632l12.475 7.182 17.231 9.92v79.676l.001.005-.001.006c0 .114.032.221.045.333.017.146.021.294.059.434l.002.007c.032.117.094.222.14.334.051.124.088.255.156.371a.036.036 0 00.004.009c.061.105.149.191.222.288.081.105.149.22.244.314l.008.01c.084.083.19.142.284.215.106.083.202.178.32.247l.013.005.011.008 34.139 19.321v34.175L5.939 144.867V29.632h-.001zm136.646 115.235l-65.352 37.625V148.31l48.399-27.628 16.953-9.677v33.862zm35.646-61.22l-29.706 17.102V66.908l17.231-9.92 12.475-7.182v33.841z"/>
                </g>
            </svg>
        </div>

        @guest
            <div class="mt-8 bg-white dark:bg-gray-800 overflow-hidden shadow sm:rounded-lg">
                <div class="grid grid-cols-1 md:grid-cols-2">
                    <div class="p-6">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laravel.com/docs" class="underline text-gray-900 dark:text-white">Documentation</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                Laravel has wonderful, thorough documentation covering every aspect of the framework. Whether you are new to the framework or have previous experience with Laravel, we recommend reading all of the documentation from beginning to end.
                            </div>
                        </div>
                    </div>

                    <div class="p-6 border-t border-gray-200 dark:border-gray-700 md:border-t-0 md:border-l">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path><path d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laracasts.com" class="underline text-gray-900 dark:text-white">Laracasts</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                Laracasts offers thousands of video tutorials on Laravel, PHP, and JavaScript development. Check them out, see for yourself, and massively level up your development skills in the process.
                            </div>
                        </div>
                    </div>

                    <div class="p-6 border-t border-gray-200 dark:border-gray-700">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laravel-news.com/" class="underline text-gray-900 dark:text-white">Laravel News</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                Laravel News is a community driven portal and newsletter aggregating all of the latest and most important news in the Laravel ecosystem, including new package releases and tutorials.
                            </div>
                        </div>
                    </div>

                    <div class="p-6 border-t border-gray-200 dark:border-gray-700 md:border-l">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold text-gray-900 dark:text-white">Vibrant Ecosystem</div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                Laravel's robust library of first-party tools and libraries, such as <a href="https://forge.laravel.com" class="underline">Forge</a>, <a href="https://vapor.laravel.com" class="underline">Vapor</a>, <a href="https://nova.laravel.com" class="underline">Nova</a>, and <a href="https://envoyer.io" class="underline">Envoyer</a> help you take your projects to the next level. Pair them with powerful open source libraries like <a href="https://laravel.com/docs/billing" class="underline">Cashier</a>, <a href="https://laravel.com/docs/dusk" class="underline">Dusk</a>, <a href="https://laravel.com/docs/broadcasting" class="underline">Echo</a>, <a href="https://laravel.com/docs/horizon" class="underline">Horizon</a>, <a href="https://laravel.com/docs/sanctum" class="underline">Sanctum</a>, <a href="https://laravel.com/docs/telescope" class="underline">Telescope</a>, and more.
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        @endguest

        @auth
            <div class="mt-8 bg-white dark:bg-gray-800 overflow-hidden shadow sm:rounded-lg">
                <div class="grid grid-cols-3">
                    <div class="p-6">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laravel.com/docs" class="underline text-gray-900 dark:text-white">Access Token</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                @dump(auth()->user()->cognito_access_token)
                            </div>
                        </div>
                    </div>

                    <div class="p-6">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path><path d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laracasts.com" class="underline text-gray-900 dark:text-white">ID Token</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                @dump(auth()->user()->cognito_id_token)
                            </div>
                        </div>
                    </div>

                    <div class="p-6">
                        <div class="flex items-center">
                            <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="w-8 h-8 text-gray-500"><path d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"></path></svg>
                            <div class="ml-4 text-lg leading-7 font-semibold"><a href="https://laravel-news.com/" class="underline text-gray-900 dark:text-white">Refresh Token</a></div>
                        </div>

                        <div class="ml-12">
                            <div class="mt-2 text-gray-600 dark:text-gray-400 text-sm">
                                @dump(auth()->user()->cognito_refresh_token)
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        @endauth

        <div class="flex justify-center mt-4 sm:items-center sm:justify-between">
            <div class="text-center text-sm text-gray-500 sm:text-left">
                <div class="flex items-center">
                    <svg fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" stroke="currentColor" class="-mt-px w-5 h-5 text-gray-400">
                        <path d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z"></path>
                    </svg>

                    <a href="https://laravel.bigcartel.com" class="ml-1 underline">
                        Shop
                    </a>

                    <svg fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" viewBox="0 0 24 24" class="ml-4 -mt-px w-5 h-5 text-gray-400">
                        <path d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"></path>
                    </svg>

                    <a href="https://github.com/sponsors/taylorotwell" class="ml-1 underline">
                        Sponsor
                    </a>
                </div>
            </div>

            <div class="ml-4 text-center text-sm text-gray-500 sm:text-right sm:ml-0">
                Laravel v{{ Illuminate\Foundation\Application::VERSION }} (PHP v{{ PHP_VERSION }})
            </div>
        </div>
    </div>
</div>
</body>
</html>
```
{{</accordion>}}

![Home: Unauthenticated](/img/articles/laravel-cognito/home-unauthenticated.png)

## Integration: Login

`app/Http/Controllers/LoginController.php`:

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Spatie\Url\Url;

class LoginController extends Controller
{
    public function __invoke(Request $request)
    {
        $cognito = Url::fromString(config('auth.cognito.idp_uri'))
            ->withPath('login')
            ->withQueryParameter('client_id', config('auth.cognito.clients.web.client_id'))
            ->withQueryParameter('redirect_uri', route('login.success'))
            ->withQueryParameter('response_type', 'code');

        return redirect()->to((string) $cognito);
    }
}
```

More information on the [`/login`](https://docs.aws.amazon.com/cognito/latest/developerguide/login-endpoint.html) endpoint.

![Hosted Login](/img/articles/laravel-cognito/cognito-login.png)

## Integration: Logout

`app/Http/Controllers/LogoutController.php`:

```php
<?php

namespace App\Http\Controllers;

use Spatie\Url\Url;

class LogoutController extends Controller
{
    public function __invoke()
    {
        $cognito = Url::fromString(config('auth.cognito.idp_uri'))
            ->withPath('logout')
            ->withQueryParameter('client_id', config('auth.cognito.clients.web.client_id'))
            ->withQueryParameter('logout_uri', route('logout.success'));

        return redirect()->to((string) $cognito);
    }
}
```

More information on the [`/logout`](https://docs.aws.amazon.com/cognito/latest/developerguide/logout-endpoint.html) endpoint.

## Integration: Login Success

You will be redirected here from Cognito with a `code` query parameter.

In this controller we will need to:

* call [`/oauth2/token`](https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html) to get tokens
* call [`/oauth2/userInfo`](https://docs.aws.amazon.com/cognito/latest/developerguide/userinfo-endpoint.html) to know which user the token belongs

`app/Http/Controllers/LoginSuccessController.php`:

```php {linenos=true}
<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Spatie\Url\Url;

class LoginSuccessController extends Controller
{
    public function __invoke(Request $request)
    {
        $code = $request->input('code');

        $uri  = (string) Url::fromString(config('auth.cognito.idp_uri'))->withPath('oauth2/token');
        $body = [
            'client_id'    => config('auth.cognito.clients.web.client_id'),
            'grant_type'   => 'authorization_code',
            'redirect_uri' => route('login.success'),
            'code'         => $code,
        ];

        $responseTokens = Http::asForm()
            ->withBasicAuth(
                config('auth.cognito.clients.web.client_id'),
                config('auth.cognito.clients.web.client_secret'),
            )
            ->post($uri, $body);
```

The response from the [`/oauth2/token`](https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html) API call will look something like this:

```php
[
  "id_token" => "eyJraWQiOiJya1wvaFRnTDBNVFZIQ1lJRm9NUWRrUFN5SGZYb3VGYWlRVXRkT25qelphQT0iLCJhbGciOiJSUzI1NiJ9.eyJhdF9oYXNoIjoiNmFOLW1IY3VoMGpLZVpQS1RMdXozdyIsInN1YiI6Ijc2N2NiY2U2LWMwZWItNGQ0NS04ZWJhLTVjYjQzNGQ0YzI3ZiIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJpc3MiOiJodHRwczpcL1wvY29nbml0by1pZHAuZXUtd2VzdC0yLmFtYXpvbmF3cy5jb21cL2V1LXdlc3QtMl92YVNFb3VHYmIiLCJjb2duaXRvOnVzZXJuYW1lIjoiNzY3Y2JjZTYtYzBlYi00ZDQ1LThlYmEtNWNiNDM0ZDRjMjdmIiwib3JpZ2luX2p0aSI6ImNmYmY3N2QxLTg2MGItNGYzYy1iNjEyLTMyNjBiZDdjMjcxYSIsImF1ZCI6IjNscGU1Y3U5N3J2ZWxuYW5rcGdxdm10Z3ZzIiwidG9rZW5fdXNlIjoiaWQiLCJhdXRoX3RpbWUiOjE2NjQwMjk4MzEsImV4cCI6MTY2NDAzMzQzMSwiaWF0IjoxNjY0MDI5ODMxLCJqdGkiOiJiOTVmMWVjNi1iNDJmLTQ1ODYtOGMyYS1mZTZjOGZhNzc1MTgiLCJlbWFpbCI6ImFsbHlAZGFmZWR0ZWFtLmNvbSJ9.PaBzQW6-C9zoA9lBg7rZyzWvHRA8UpZc8KSL-DyGk3ZChp7UxT8KldSMzoKR_oQy1eUlUlwZAoMwE7UrS51pLB6nllv4jbhCBW4123gXD6h-H6EhKnV0RpaXEmxY1x1LBsfH1DD-MI8AMCQZm_Pk8WbbGPT36UuNzI_HjUNu_sBcNt6xWlvcmppeTkD4E_Pi1lM7TCfQk5buvGRYLbZtOpZ7F-59ok7zCfv24CpuImxKV4NKuszMBejmoRxL7LQLY1YbULbW6oTjZ-TWQ0OEWvnY486gikorLpMRKBiGq1uwMm36q8FO1KGGORpuuf0JGAtfS-HE6mvue62KiD0Usg ◀"
  "access_token" => "eyJraWQiOiJhWlhzQ1JHUXhzUUxlTSs1OTdpUCtsbFpaNEc4Z3NFMlJvMnNUc3N0WGdBPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI3NjdjYmNlNi1jMGViLTRkNDUtOGViYS01Y2I0MzRkNGMyN2YiLCJpc3MiOiJodHRwczpcL1wvY29nbml0by1pZHAuZXUtd2VzdC0yLmFtYXpvbmF3cy5jb21cL2V1LXdlc3QtMl92YVNFb3VHYmIiLCJ2ZXJzaW9uIjoyLCJjbGllbnRfaWQiOiIzbHBlNWN1OTdydmVsbmFua3BncXZtdGd2cyIsIm9yaWdpbl9qdGkiOiJjZmJmNzdkMS04NjBiLTRmM2MtYjYxMi0zMjYwYmQ3YzI3MWEiLCJ0b2tlbl91c2UiOiJhY2Nlc3MiLCJzY29wZSI6InBob25lIG9wZW5pZCBwcm9maWxlIGVtYWlsIiwiYXV0aF90aW1lIjoxNjY0MDI5ODMxLCJleHAiOjE2NjQwMzM0MzEsImlhdCI6MTY2NDAyOTgzMSwianRpIjoiNzQ1NzAzNmUtZjJhMi00NTk1LWJjOGQtNjJiMTEwZWZjODRiIiwidXNlcm5hbWUiOiI3NjdjYmNlNi1jMGViLTRkNDUtOGViYS01Y2I0MzRkNGMyN2YifQ.gyw70QBcxbb_gQGwwUFqt9bTuQD-s1NZJD0CBjX5ikaXnAqfhVt_UKCPAVRJOoVJ0Q4f7T18uI69BUvqSc8pJgSxv5NzYM_LpCg7sHLdoIqEt4VJZ_p0M73CHp4Acxt5hpnAR6ueR-Xbv1Y3Merbn5wFwDrzXOzqSKbaUBmcXzeEo9OLmbtp58HbivA3mR0jqtvMm-KJ57j5QpsPsj_OEOjnfz_b8FQFwPfs3-soP9IzWUoeG5ZzAvqpLpjo7Qr73MBAusSNaZTYK14MiYMbH-_R-sii0uXV71u0KJO1mTcJZnlSBItLzIYClxAxSqd3at0e6Oobr3EnX9CYGgsGJw ◀"
  "refresh_token" => "eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BRVAifQ.Zr3i3HXermZoF1ayamtHZNv0G7aCbel0JiFSdDXYmfkAjFr-9fYUMX9y3yTVPInVEb8nvFyK-T9eLu3sLAgU7HKn2eLfP507UZr_kBDZW6Wm24oSmYxz7DAvkftwWRynjkKqjq8teSLxMyHehGv6CPPt1BrXGxeRUG1tKLz36G4szXlRxof3FvKBkP4_-Ncl6dW5wTRocVS8F2_3oAMOSa8oxNksbqGKEuOJoOBknAVczFWetkbHWmq4IY2HrIda3nbsXxKKiKWT3-MW4949NXvISibnvYzOpZPlZ4_bSu7uQISc1Cqb3z1sBZD7BKzqnhkJiov11JaKEzAu5dIFew.jvXqoUtX_9-jV4-C.iszbcH4OlT3eZd8hOtk4xQP25Esfz2uGqofkULgsh28SQvH_E9s7PZgbPIbQO-k89pS2CWHElcucKP7cvkArTBIIhzfawzbt-4Fe14_KA8cYLCpdtijGb49POalIbMoPdphuifAlwoCFWqEPDGOiIAM3gby7o9XMBJcZyEu7k7x4spmyWcxkGi9GCSd9sIn6sGU-v-iHy7UPNRiP_EAueOIFpl-uuoXhMKaz_n6tYLoo9dadNDitlM5jQhK0ITmNVB89nFUluvn1kbSWDfbXOrbH53eFJw70ltnOnmZYFv-Fi-1_VIEYPJcYtL7QmLCfAT9QgddRqaAzaNAfYxBj5pYFVY7LFYWYKFnM2GhEOvbxAXixOJR_hhzCMrpLDtExe_Yz654WyTwm0umc0he2qyPwjaQlYJhJ2dEnu5jtStUCM2viAPtXXVQNi4p8I9VAR0_ptVPfJSziQ1veju9ATWwodfe7TQ1QQqXWL26ZN0cICVYxEsIwa87S8PBzN-mLkV5BDg37TJp7L1EzvrvMeYzezDJ2D7x-PTDgv97W45gYebm918I9LiKFCCWuqr5Te5u11Z9TI1tSDoGlKLRq0XChjNQDuKhtjfmBDD2L0WGSAICDKslR1gSYLZITEFaptvoXGkc3TuHPyCuNxLVWne7rSTiz1QBhY9U-udyi-rBnxb3LbQWH1kGS5rpBKQzu6MuPyLg3pHAORvxlRYfFOQdAGsnWrI1234nVcD3P854zu0cQKNcoKn-eYLYQpCntbdzz0G9sGa77k4Iki3LbhrGISQj2KFAp7EsEa4798ANd_o__vq1msVL6l4sz0C1wq8P2tVkiUkYyvGNrPxzcoXosBouhj83P-dh16auN7hdVxX-Yl13fNHpCa8gh9UbEQ-Olqal1G3AoB6DNhs67pc8WRjW2_mom5aVeS9uOzMlWLdmXWU3n_ae5NP6I1J61mCTZoN25qELGERBDkr8qdpCgnLRBlhAdQMrIdSYI42YSs694r_Krw-VLAdbF1AaFIUdZlDioGB1T39mE1a7UOhgHSKVeogQAV2hpIxBpy8PjvFGE-bcdD1SH_BSGiRww7TIQneLwPNp_InMmEp3gaB3bH5Z8MfGTd4RxCvIbzB2AzToKA5huaNeIsfmfmKD-6FfjEK8d5Ba2BymbU_23M3oQIldzxo3dMxSrgtJi1FI1P_0NA5dVS4I8UlZcH3DMQ5x4DZJT5uT0Oytvy_wADs3SHmgQ07Ns_zmMub-q2LRFuxVJHm4.pKGqMLfbWxDcCOudMOmIfQ ◀"
  "expires_in" => 3600
  "token_type" => "Bearer"
]
```

```php {linenos=true, linenostart=32}
        $uri     = (string) Url::fromString(config('auth.cognito.idp_uri'))->withPath('oauth2/userInfo');
        $token   = $responseTokens->json('access_token');
        $headers = [
            'Authorization' => 'Bearer ' . $token
        ];

        $responseUserInfo = Http::withHeaders($headers)->get($uri);
```

The response from [`/oauth2/userInfo`](https://docs.aws.amazon.com/cognito/latest/developerguide/userinfo-endpoint.html) will look something like this:

```php
[
  "sub" => "767cbce6-c0eb-4d45-8eba-5cb434d4c27f"
  "email_verified" => "true"
  "email" => "ally@dafedteam.com"
  "username" => "767cbce6-c0eb-4d45-8eba-5cb434d4c27f"
]
```

Finally, we will try and match the user to which the tokens belong, save them in our database, and log the user in.

```php {linenos=true, linenostart=40}
        /** @var User $user */
        $user = User::query()
            ->where('email', $responseUserInfo->json('email'))
            ->firstOrFail();

        $user->setCognitoTokensFromResponse($responseTokens);

        Auth::guard('web')->login($user);

        return redirect()->route('index');
    }
}
```

{{<accordion title="`app/Http/Controllers/LoginSuccessController.php`">}}
```php
<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Spatie\Url\Url;

class LoginSuccessController extends Controller
{
    public function __invoke(Request $request)
    {
        // 1. Get an access token using the authentication code
        // 2. Get the user info using the access token to do some auth on our side
        $code = $request->input('code');

        // https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html
        $uri  = (string) Url::fromString(config('auth.cognito.idp_uri'))->withPath('oauth2/token');
        $body = [
            'client_id'    => config('auth.cognito.clients.web.client_id'),
            'grant_type'   => 'authorization_code',
            'redirect_uri' => route('login.success'),
            'code'         => $code,
        ];

        $responseTokens = Http::asForm()
            ->withBasicAuth(
                config('auth.cognito.clients.web.client_id'),
                config('auth.cognito.clients.web.client_secret'),
            )
            ->post($uri, $body);

        // https://docs.aws.amazon.com/cognito/latest/developerguide/userinfo-endpoint.html
        $uri     = (string) Url::fromString(config('auth.cognito.idp_uri'))->withPath('oauth2/userInfo');
        $token   = $responseTokens->json('access_token');
        $headers = [
            'Authorization' => 'Bearer ' . $token
        ];

        $responseUserInfo = Http::withHeaders($headers)->get($uri);

        /** @var User $user */
        $user = User::query()
            ->where('email', $responseUserInfo->json('email'))
            ->firstOrFail();

        $user->setCognitoTokensFromResponse($responseTokens);

        Auth::guard('web')->login($user);

        return redirect()->route('index');
    }
}
```
{{</accordion>}}

![Home: authenticated](/img/articles/laravel-cognito/home-authenticated.png)

## Integration: Logout Success

Like with the login endpoint, you will be redirected to this page. The logout endpoint does not revoke tokens, I have decided to do this.

To summarise this will:

* call [`/oauth2/revoke`](https://docs.aws.amazon.com/cognito/latest/developerguide/revocation-endpoint.html)
* remove tokens from our database
* logout user session in our application

`app/Http/Controllers/LogoutSuccessController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;
use Spatie\Url\Url;

class LogoutSuccessController extends Controller
{
    public function __invoke()
    {
        if (auth()->guest()) {
            return redirect()->route('index');
        }

        /** @var ?User $user */
        $user = auth()->user();

        if (filled($user->cognito_refresh_token)) {
            $uri  = (string) Url::fromString(config('auth.cognito.idp_uri'))->withPath('/oauth2/revoke');
            $body = [
                'client_id' => config('auth.cognito.clients.web.client_id'),
                'token'     => $user->cognito_refresh_token,
            ];

            Http::asForm()
                ->withBasicAuth(
                    config('auth.cognito.clients.web.client_id'),
                    config('auth.cognito.clients.web.client_secret'),
                )
                ->post($uri, $body);
        }

        $user->resetCognitoTokens();

        Auth::guard('web')->logout();

        return redirect()->route('index');
    }
}
```

## Integration: System Login

For demonstration purposes this will be a simple console command.

`app/Console/Command/CreateAdminToken.php`:

```php {linenos=true}
<?php

namespace App\Console\Commands;

use App\Models\User;
use Aws\CognitoIdentityProvider\CognitoIdentityProviderClient;
use Aws\Credentials\Credentials;
use Aws\Result;
use Illuminate\Console\Command;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Arr;
use Illuminate\Support\Str;

class CreateAdminToken extends Command
{
    protected $signature = 'token:create';

    protected $description = 'Create admin token';

    public function handle(): int
    {
        $cognito = new CognitoIdentityProviderClient([
            'region' => 'eu-west-2',
            'version' => '2016-04-18',
            'credentials' => new Credentials(
                config('auth.cognito.aws_access_key'),
                config('auth.cognito.aws_secret_access_key')
            ),
        ]);

        $data = [
            'ClientId'   => config('auth.cognito.clients.system.client_id'),
            'UserPoolId' => config('auth.cognito.user_pool_id'),
            'AuthFlow'   => 'ADMIN_NO_SRP_AUTH',
            'AuthParameters' => [
                'USERNAME' => $user = config('auth.cognito.clients.system.admin.user'),
                'PASSWORD' => config('auth.cognito.clients.system.admin.pass'),
                'SECRET_HASH' => $this->hmacClientSecret($user),
            ],
        ];

        $result = $cognito->adminInitiateAuth($data);
```

The AWS response will look something like this:

```text
Aws\Result {#675
  -data: array:3 [
    "ChallengeParameters" => []
    "AuthenticationResult" => array:5 [
      "AccessToken" => "eyJraWQiOiJhWlhzQ1JHUXhzUUxlTSs1OTdpUCtsbFpaNEc4Z3NFMlJvMnNUc3N0WGdBPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI3NjdjYmNlNi1jMGViLTRkNDUtOGViYS01Y2I0MzRkNGMyN2YiLCJpc3MiOiJodHRwczpcL1wvY29nbml0by1pZHAuZXUtd2VzdC0yLmFtYXpvbmF3cy5jb21cL2V1LXdlc3QtMl92YVNFb3VHYmIiLCJjbGllbnRfaWQiOiI0M3N1cjhhbWlwN2F1MGFiOWJwdGU3dmRhNiIsIm9yaWdpbl9qdGkiOiIyY2U4NDE0Zi0xYjhhLTRhYTctOTI4Yi00ZDBlNmQyNzdiMzEiLCJldmVudF9pZCI6ImIwMGM2MjdlLTY3YWUtNGMzNy04M2Q1LTViMmY5ZTZkYjMyMyIsInRva2VuX3VzZSI6ImFjY2VzcyIsInNjb3BlIjoiYXdzLmNvZ25pdG8uc2lnbmluLnVzZXIuYWRtaW4iLCJhdXRoX3RpbWUiOjE2NjQwMzUzMjQsImV4cCI6MTY2NDAzODkyNCwiaWF0IjoxNjY0MDM1MzI0LCJqdGkiOiIxMTY4OWQyNS1hM2Y4LTRlODAtYmQyZS1kYjVhODA5YzNmOWQiLCJ1c2VybmFtZSI6Ijc2N2NiY2U2LWMwZWItNGQ0NS04ZWJhLTVjYjQzNGQ0YzI3ZiJ9.Mkon3xgxJ4pb3PJ9n5_twIdCO791fbXMtYl0QpC6kpXBPtMv5jaSdvkbd9liCymiaJVaBhGXn2i51mfibIrhFEemUpyux8j238E5QBhHbyMeLBVJ2my2tgNxN7Djfae_wE7uH2dF13cJesbEey-qy1vTeq5bz9lPzuESpG-hIXtswqmanETVSV-0GcjWvyxpPFBpKr7IwVH-n1o6qi2L__uQb8aqgTriJTWOFzbDfLz8EhyVfzMI79LOS-dreyPtDwG9gu1_zD60pyPG9UJCfLcyQqnRlF1lS9XkCiJ8zUC-NcT5i82eU__fOVFizW3W8huIrb7XkmLTzfTHqwghAQ"
      "ExpiresIn" => 3600
      "TokenType" => "Bearer"
      "RefreshToken" => "eyJjdHkiOiJKV1QiLCJlbmMiOiJBMjU2R0NNIiwiYWxnIjoiUlNBLU9BRVAifQ.W5ZXUj_Ok23rWuIX2d9GNJ3QUEpZ2uzfzU6fH-yJVNOG0qffX9kFpcGaHUTQS_UypJZibAZTf663f_vNWCS2_pto6YO3v1XG0vVK-BYiSMmurQ-AqG0dHayr08Ef23a43FLWrrEOoIJa9L5Vxc78c5OnWCi223uzgHfmjrQNpSPDIsMDYHIa-zUQhyYhNK6Afq0ZeNvfVu5Gbv_BO5tEgb-4Dg7wndX82K526dbaJhLmH37d_ji2KosDRLWZWJbNwZJtkbZi2DCFwLP1iENzhmELgl9JjwmiIv3DlsturCQ9iTNWA6DwkFoFrS3F51IKoyhcP1LSlqdsnhVjk8iXVQ.vUt3b7rl1nF174Mc.4FZbJMLqPBGjU8yMvN9tflNvC3vbjpo7a_DRXbladBva_mnU8DXCq1AN76xGpTFS_G8BEjEe5m3mXBhyGWy56zMopwMWnMWrq6CiUW20NoTFnpo7k0PvmLF3Shjskp5pHSFQei4WU_NGuZ_Kutnnf96rXuKNPqWWunBj8men4axc_It_cFy_UNcPwhwJ8XN6XBv7GkuddODRibyZRF9nljqA7Pcu7oQNVTd0vRdUQy06hF5Exa688stF4bK51m2O_kHXmQ2dWDEj5AwPh-UdDjeMxGEXnv_eESD6IItvQhij2ETb_oLiSfyA6TXlw0Swh74BRCSK2y4bbi6jr25Rz1LepY7V_6l3m2BpdiRJRS6HKLr4rwen2uHbw01DRfkOYGrRGtD1oXkeHgolDWTlFyFtJYCoKewi6e-KDuKGshY_1DVPhSUo764_DYt339EJjeTahdxZIHULs8soDW6wVkVaSj-knZtHF0NMZUWTRyjONn_4SoUGYoG_AphcnH7WMSPd5N7vzJUPPSYud8dqVk79sOeeZT6CiyL9-rxvr7Ni2X2FeYYrrL3zFM5aI97SeLyGge6bMULgL5y6Dg8f4cGg2CIFo9ej8ZRH-f4bCvdml12O-TxHUojQmvLQXj28rIGxwThxG3a4thDgO8ZVzrZDW3FTndUZXVw4wut3x_epIh2_nHSx7tZfWOWWBd8yLNcpnlM7haxBW6s7MpLTtXihN0Q2cpfWkIATBcH7SyIVCX9s2CcBVQCb6AJTzyGWTfQFCi871DNI19LRUuC9szGbWsaZuRW1CVOb5mQqmVxZPQHmF8L10Z0SFfEKuQlys3N5eqQiE8yxoZSp_NVqtDwwAWzVD1uoXrWrXfzhHSscuSxYEl4C7J00wS14irOBjN3FHCljM6Mwr-WI0OsgO2gANxmy_--icBaFnJzj9QSH75SheLiIL-wdiiohHeNpL-7gHrHr9GCUdl78mBXuzk2wUz0_MiyEloeD2Me_X7DhsdEESYSplxn-zlUJCVmCVl_BIIXARd-QI1FpnYAg1cCDl8sW93CNiIhUzRPOQAsydKUS5EQl0EkiIENYnxePJUF9mM5b-KQRWli7YqXHph7iYrnpcllQDGqmMtzJqjiaZWhLxL4AuP61ev8MSiYy6UOvPtwlq0JcsLkjUWMRQijoL3uWB2xhkU2oHb3GGKx6i91EhtAdF9XlsLpQi7j_fD7bA8uCu5kwufIPgpy5T9m_Shou63T0QfXGHccCwiY6KeMvsRYxBvZ9GJS3zmmvfKt1pNAmCiTKMIthib8kYFPKxIxny-2qmo84oiPTfLNR3CmLQ-3d0jtYwJM.MGPcEOqqhK11ZU2jiHuxow"
      "IdToken" => "eyJraWQiOiJya1wvaFRnTDBNVFZIQ1lJRm9NUWRrUFN5SGZYb3VGYWlRVXRkT25qelphQT0iLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI3NjdjYmNlNi1jMGViLTRkNDUtOGViYS01Y2I0MzRkNGMyN2YiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaXNzIjoiaHR0cHM6XC9cL2NvZ25pdG8taWRwLmV1LXdlc3QtMi5hbWF6b25hd3MuY29tXC9ldS13ZXN0LTJfdmFTRW91R2JiIiwiY29nbml0bzp1c2VybmFtZSI6Ijc2N2NiY2U2LWMwZWItNGQ0NS04ZWJhLTVjYjQzNGQ0YzI3ZiIsIm9yaWdpbl9qdGkiOiIyY2U4NDE0Zi0xYjhhLTRhYTctOTI4Yi00ZDBlNmQyNzdiMzEiLCJhdWQiOiI0M3N1cjhhbWlwN2F1MGFiOWJwdGU3dmRhNiIsImV2ZW50X2lkIjoiYjAwYzYyN2UtNjdhZS00YzM3LTgzZDUtNWIyZjllNmRiMzIzIiwidG9rZW5fdXNlIjoiaWQiLCJhdXRoX3RpbWUiOjE2NjQwMzUzMjQsImV4cCI6MTY2NDAzODkyNCwiaWF0IjoxNjY0MDM1MzI0LCJqdGkiOiIwYjdjM2JlMS01MTRiLTQyMmUtYmQ1NS0wODA4YmRjMTgxMmMiLCJlbWFpbCI6ImFsbHlAZGFmZWR0ZWFtLmNvbSJ9.lbHytRoN6Oej0Cfsv-kT0Oje9Ip1lEjDVaD977l4Aquxa09vSvZhbMee_8QW2D9EJMrDiJ2zoyqJk2RQHCfslUbWxQvxtUys7NgdYNeQnf4yMWujs9uNv2wqPa5QvYQ14WVvJJZt4ght3GEvOniCQR65Cu7IlJyjJ1eSP2jsMeyJISQ_p8_KPhlhqdg62ajoSlQkbe6N9T8QiY1KoX-DIjTmyUbG73t0LMTdep1ICKc_NnW3qBfodW43J6ifSyaQ75TJl5l1nEdb8-fBUmyZg8MQEpZyZ-LMVmG-c6zI1QBCGZdhc0p24nnbDHp60dWYkNyLQ8Yr-uj4KgE0z_byog"
    ]
    "@metadata" => array:4 [
      "statusCode" => 200
      "effectiveUri" => "https://cognito-idp.eu-west-2.amazonaws.com"
      "headers" => array:5 [
        "date" => "Sat, 24 Sep 2022 16:02:04 GMT"
        "content-type" => "application/x-amz-json-1.1"
        "content-length" => "4077"
        "connection" => "keep-alive"
        "x-amzn-requestid" => "b00c627e-67ae-4c37-83d5-5b2f9e6db323"
      ]
      "transferStats" => array:1 [
        "http" => array:1 [
          0 => []
        ]
      ]
    ]
  ]
  -monitoringEvents: []
}
```

We will canonicalise the AWS `Result` to a HTTP response which we have used earlier in the `HasCognitoTokens` trait.

```php {linenos=true, linenostart=44}
        $response = $this->convertAwsResultToResponse($result);

        /** @var User $user */
        $user = User::query()->where('email', $user)->first();
        $user->setCognitoTokensFromResponse($response);

        return self::SUCCESS;
    }

    private function convertAwsResultToResponse(Result $result): Response
    {
        $tokens = collect(Arr::get($result, 'AuthenticationResult'))
            ->mapWithKeys(function ($value, $key) {
                return [
                    (string) Str::of($key)->snake() => $value,
                ];
            });

        $metadata = $result->offsetGet('@metadata');
        $status   = Arr::get($metadata, 'statusCode');
        $headers  = Arr::get($metadata, 'headers');

        $response = new \GuzzleHttp\Psr7\Response($status, $headers, $tokens);

        return new Response($response);
    }
    
    private function hmacClientSecret(string $user): string
    {
        return base64_encode(
            hash_hmac(
                'sha256',
                sprintf(
                    '%s%s',
                    $user,
                    config('auth.cognito.clients.system.client_id')
                ),
                config('auth.cognito.clients.system.client_secret'),
                true
            )
        );
    }
}
```

## Integration: Decode JWT

Just a simple console command to decode a given token.

You will need to download the `jwks.json` and place it in the `base_path`, i.e. root, of the laravel integration.

e.g.

```bash
# url formats:
# "https://${aws_cognito_user_pool.dafed.endpoint}/.well-known/jwks.json"
# https://cognito-idp.USER_POOL_REGION.amazonaws.com/USER_POOL_ID/.well-known/jwks.json
curl -o src/jwks.json "$(terraform output -raw cognito_json_web_key_set)"
```

`app/Console/Command/DecodeToken.php`:

```php
<?php

namespace App\Console\Commands;

use Firebase\JWT\JWK;
use Firebase\JWT\JWT;
use Illuminate\Console\Command;
use Throwable;

class DecodeToken extends Command
{
    protected $signature = 'token:decode {token : The token to validate}';

    protected $description = 'Decode a token';

    public function handle(): int
    {
        if (!file_exists($file = base_path('jwks.json'))) {
            // run from root with terraform files:
            // curl -o src/jwks.json "$(terraform output -raw cognito_json_web_key_set)"
            $this->alert('No <fg=white>jwks.json</> found in <fg=white>base_path</>');
            $this->info('You can download <fg=white>jwks.json</> at <fg=white>https://cognito-idp.<fg=red>USER_POOL_REGION</>.amazonaws.com/<fg=red>USER_POOL_ID</>/.well-known/jwks.json</>');

            return self::FAILURE;
        }

        $jwks = json_decode(file_get_contents($file), true);
        $keys = JWK::parseKeySet($jwks);

        try {
            $decoded = JWT::decode(
                $this->argument('token'),
                $keys
            );
            dump($decoded);

            return self::SUCCESS;
        } catch (Throwable $e) {
            $this->alert($e->getMessage());
            return self::FAILURE;
        }
    }
}
```

Examples:

{{<accordion title="Decoding an `access_token` for a user authenticated using `web` hosted UI client">}}
```json
{
   "sub": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
   "iss": "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_vaSEouGbb",
   "version": 2,
   "client_id": "3lpe5cu97rvelnankpgqvmtgvs",
   "origin_jti": "9f70d7b4-28c2-4667-93cd-1f34b4f404d5",
   "event_id": "d8038a9c-3b96-4012-b8df-e9c27ecd6fcc",
   "token_use": "access",
   "scope": "phone openid profile email",
   "auth_time": 1664037766,
   "exp": 1664041366,
   "iat": 1664037766,
   "jti": "d133432b-3b57-4342-ba4b-310d61e31d36",
   "username": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f"
}
```
{{</accordion>}}

{{<accordion title="Decoding an `id_token` for a user authenticated using `web` hosted UI client">}}
```json
{
  "at_hash": "1KNEV9W7X9rUCTpcQyqjOg",
  "sub": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
  "email_verified": true,
  "iss": "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_vaSEouGbb",
  "cognito:username": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
  "origin_jti": "9f70d7b4-28c2-4667-93cd-1f34b4f404d5",
  "aud": "3lpe5cu97rvelnankpgqvmtgvs",
  "event_id": "d8038a9c-3b96-4012-b8df-e9c27ecd6fcc",
  "token_use": "id",
  "auth_time": 1664037766,
  "exp": 1664041366,
  "iat": 1664037766,
  "jti": "14565821-fa33-45c9-a14c-bfa3bbea9837",
  "email": "ally@dafedteam.com"
}
```
{{</accordion>}}

{{<accordion title="Decoding an `access_token` for a user authenticated using `system` client">}}
```json
{
  "sub": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
  "iss": "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_vaSEouGbb",
  "client_id": "43sur8amip7au0ab9bpte7vda6",
  "origin_jti": "dc9da734-65a4-4dae-9dce-b36e0527863e",
  "event_id": "57881c09-9c3f-4f33-b113-81bb41ab7a39",
  "token_use": "access",
  "scope": "aws.cognito.signin.user.admin",
  "auth_time": 1664037953,
  "exp": 1664041553,
  "iat": 1664037953,
  "jti": "02388294-20a4-413f-b9aa-7b1a552e2fbe",
  "username": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f"
}
```
{{</accordion>}}

{{<accordion title="Decoding an `id_token` for a user authenticated using `system` client">}}
```json
{
  "sub": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
  "email_verified": true,
  "iss": "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_vaSEouGbb",
  "cognito:username": "767cbce6-c0eb-4d45-8eba-5cb434d4c27f",
  "origin_jti": "dc9da734-65a4-4dae-9dce-b36e0527863e",
  "aud": "43sur8amip7au0ab9bpte7vda6",
  "event_id": "57881c09-9c3f-4f33-b113-81bb41ab7a39",
  "token_use": "id",
  "auth_time": 1664037953,
  "exp": 1664041553,
  "iat": 1664037953,
  "jti": "93c30197-e5ec-4022-b00c-f6d86c437bc1",
  "email": "ally@dafedteam.com"
}
```
{{</accordion>}}

Good luck understanding Cognito! I certainly don't...

GitHub repo [here](https://github.com/alistaircol/cognito-laravel-integration)
