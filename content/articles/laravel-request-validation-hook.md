---
title: "Standard JSON validation response in Laravel"
author: "Ally"
summary: "Using `failedValidation` for standard JSON responses on validation error(s)."
publishDate: 2020-11-17T00:00:00+01:00
tags: ['php', 'laravel']
draft: false
---

Doing validation in the controller kinda sucks! We don't want fat controllers. One way to stop fat controllers is creating a custom `Request`, which will store the validation rules, messages, etc.

Altering the way a `Request` is returned when validation is in a custom `Request` object might be something you want to consider.

Returning a `Response` with a redirect url and `MessageBag` might not be what you want, and can be laborious to change this on a per-controller basis.

*A default API call where the validation has failed:*

![Login](/img/articles/laravel-validation/default-failed.png)

Overriding the `failedValidation` in a new `Request` might be what you need to return the validation errors in a standard json format! This post will walk you through this.

## `Request`s

Lets start by making a couple of `Request`s.

```text
$ php artisan make:request --help
Description:
  Create a new form request class

Usage:
  make:request <name>

Arguments:
  name                  The name of the class

Options:
  -h, --help            Display this help message
  -q, --quiet           Do not output any message
  -V, --version         Display this application version
      --ansi            Force ANSI output
      --no-ansi         Disable ANSI output
  -n, --no-interaction  Do not ask any interactive question
      --env[=ENV]       The environment the command should run under
  -v|vv|vvv, --verbose  Increase the verbosity of messages: 1 for normal output, 2 for more verbose output and 3 for debug
```

We'll make a `JsonRequest` that our new API Requests will extend.

```bash
php artisan make:request JsonRequest
```

`app/Http/Requests/JsonRequest.php`: *We'll come back to this one later!*

```php
<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class JsonRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * @return bool
     */
    public function authorize()
    {
        return false;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array
     */
    public function rules()
    {
        return [
            //
        ];
    }
}

```

Next, we'll make a new `TestRequest` which will extend our new `JsonRequest`, and will add some validation rules.

```bash
php artisan make:request Api/TestRequest
```

`app/Http/Requests/Api/TestRequest.php`:

```diff
 <?php
 
 namespace App\Http\Requests\Api;
 
-use Illuminate\Foundation\Http\FormRequest;
+use App\Http\Requests\JsonRequest;
 
-class TestRequest extends FormRequest
+class TestRequest extends JsonRequest
 {
     /**
      * Determine if the user is authorized to make this request.
      *
      * @return bool
      */
     public function authorize()
     {
-         return false;
+         return true;
     }
 
     /**
      * Get the validation rules that apply to the request.
      *
      * @return array
      */
     public function rules()
     {
         return [
-             //
+             'field' => ['required'],
         ];
     }
 }
 
```

## `Controller`s

```text
$ php artisan make:controller --help
Description:
  Create a new controller class

Usage:
  make:controller [options] [--] <name>

Arguments:
  name                   The name of the class

Options:
      --api              Exclude the create and edit methods from the controller.
      --force            Create the class even if the controller already exists
  -i, --invokable        Generate a single method, invokable controller class.
  -m, --model[=MODEL]    Generate a resource controller for the given model.
  -p, --parent[=PARENT]  Generate a nested resource controller class.
  -r, --resource         Generate a resource controller class.
  -h, --help             Display this help message
  -q, --quiet            Do not output any message
  -V, --version          Display this application version
      --ansi             Force ANSI output
      --no-ansi          Disable ANSI output
  -n, --no-interaction   Do not ask any interactive question
      --env[=ENV]        The environment the command should run under
  -v|vv|vvv, --verbose   Increase the verbosity of messages: 1 for normal output, 2 for more verbose output and 3 for debug
```

```bash
 php artisan make:controller --api --invokable Api/TestController
```

I use `--invokable` because I like single action controllers.

Changing the argument in `__invokable` to the `TestRequest` will trigger the validation process. Laravel just takes care of it.

`app/Http/Controller/Api/TestController.php`:

```diff
 <?php
 
 namespace App\Http\Controllers\Api;
 
 use App\Http\Controllers\Controller;
-use Illuminate\Http\Request;
+use App\Http\Requests\Api\TestRequest;

 class TestController extends Controller
 {
     /**
      * Handle the incoming request.
      *
      * @param  \Illuminate\Http\Request  $request
      * @return \Illuminate\Http\Response
      */
-     public function __invoke(Request $request)
+     public function __invoke(TestRequest $request)
     {
+        return response()->json(['success' => true], 200);
     }
 }
 
```

## Routes

Just the last line for testing.

`routes/api.php`:

```php
<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| is assigned the "api" middleware group. Enjoy building your API!
|
*/

Route::middleware('auth:api')->get('/user', function (Request $request) {
    return $request->user();
});

Route::post('test', \App\Http\Controllers\Api\TestController::class);

```
## Testing

| Without `field` param | With `field` param |
|-----------------------|---------------------|
| ![fail](/img/articles/laravel-validation/default-failed.png) | ![pass](/img/articles/laravel-validation/default-passed.png) | 

Nothing has changed, unsurprisingly. The next step will fix that!

## `Request`s Again

Override the `failedValidation` in `app/Http/Requests/JsonRequest.php`:

```php
<?php

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Response;
use Illuminate\Validation\ValidationException;

class JsonRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * @return bool
     */
    public function authorize()
    {
        return false;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array
     */
    public function rules()
    {
        return [
            //
        ];
    }

    /**
     * Handle a failed validation attempt.
     *
     * @param Validator $validator
     * @throws ValidationException
     */
    protected function failedValidation(Validator $validator)
    {
        throw new ValidationException(
            $validator,
            response()->json(
                [
                    'validation_errors' => $validator->errors()
                ],
                Response::HTTP_UNPROCESSABLE_ENTITY
            )
        );
    }
}

```

## Testing Again

Great success!

![Login](/img/articles/laravel-validation/override-failed.png)

| Without `field` param | With `field` param |
|-----------------------|---------------------|
| ![fail](/img/articles/laravel-validation/override-failed.png) | ![pass](/img/articles/laravel-validation/default-passed.png) | 

Ultimately we are overriding a trait in `FormRequest`, `Illuminate/Validation/ValidatesWhenResolvedTrait.php` - so have a look in there and see if there's something else you can think of.
