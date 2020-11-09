---
title: "Single action Laravel controllers and FQCN in route definitions"
author: "Ally"
summary: "Slim single action controllers and IDE friendly FQCN route definitions in Laravel."
publishDate: 2020-11-08T00:00:00+01:00
tags: ['php', 'laravel']
draft: false
---

When I start a new Laravel project, I like to keep my controllers as slim as possible. To accomplish this I like to have single action/responsibility controllers.

An example controller:

`app/Http/Controllers/Api/V1/FileUploadController.php`:

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Config\Queue;
use App\Events\CanonicaliseUploadedJobsFile;
use App\Http\Controllers\Controller;
use App\Jobs\ImportUploadedJobsFile;
use App\Jobs\ValidateUploadedJobsFile;
use App\Models\UploadedJobsFile;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Http\UploadedFile;
use League\Csv\Reader;
use Ramsey\Uuid\Uuid;

/**
 * Class LoginController
 * @package App\Http\Controllers\Api
 */
class FileUploadController extends Controller
{
    /**
     * @param Request $request
     * @return \Illuminate\Http\JsonResponse
     * @throws \Throwable
     */
    public function __invoke(Request $request)
    {
        $files = $request->file();
        if ($files === null || empty($files)) {
            return response()->json(
                [
                    'success' => false,
                    'error' => 'No file was attached for upload.',
                ],
                Response::HTTP_BAD_REQUEST
            );
        }

        $uploaded_jobs_files = [];

        // maybe queue the upload as event not a job and chain validate after upload?
        foreach ($files as $file) {
            $uploaded_jobs_files[] = $this->saveUploadedJobsFile($file, $request);
        }

        foreach ($uploaded_jobs_files as $uploaded_jobs_file) {
            ValidateUploadedJobsFile::withChain([
                new ImportUploadedJobsFile($uploaded_jobs_file)
            ])->dispatch($uploaded_jobs_file);
        }

        return response()->json(
            [
                'success' => true,
                'uploaded_jobs_file_ids' => $uploaded_jobs_files,
            ],
            Response::HTTP_OK
        );
    }
}
```

To configure this endpoint, typically you would do, in `routes/api.php`:

```php
<?php

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

Route::post('login', 'LoginController@login');

Route::middleware(['auth:api'])->prefix('v1')->group(function () {
    Route::post('file', 'FileUploadController@upload');
});
```

However, we can do better!

Open up `app/Providers/RouteServiceProvider.php` and remove the namespace in the relevant route map, for this example it is line 80.

```php {linenos=true}
<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\RouteServiceProvider as ServiceProvider;
use Illuminate\Support\Facades\Route;

class RouteServiceProvider extends ServiceProvider
{
    /**
     * This namespace is applied to your controller routes.
     *
     * In addition, it is set as the URL generator's root namespace.
     *
     * @var string
     */
    protected $namespace = 'App\Http\Controllers';

    /**
     * The path to the "home" route for your application.
     *
     * @var string
     */
    public const HOME = '/home';

    /**
     * Define your route model bindings, pattern filters, etc.
     *
     * @return void
     */
    public function boot()
    {
        //

        parent::boot();
    }

    /**
     * Define the routes for the application.
     *
     * @return void
     */
    public function map()
    {
        $this->mapApiRoutes();

        $this->mapWebRoutes();

        //
    }

    /**
     * Define the "web" routes for the application.
     *
     * These routes all receive session state, CSRF protection, etc.
     *
     * @return void
     */
    protected function mapWebRoutes()
    {
        Route::middleware('web')
            ->namespace($this->namespace)
            ->group(base_path('routes/web.php'));
    }

    /**
     * Define the "api" routes for the application.
     *
     * These routes are typically stateless.
     *
     * AC: have removed namespace so we can use FQCN in api.php :)
     *
     * @return void
     */
    protected function mapApiRoutes()
    {
        Route::prefix('api')
            ->middleware('api')
            // ->namespace($this->namespace)
            ->group(base_path('routes/api.php'));
    }
}
```

Then we can use the FQCN of the controller in the route definition. Route-model binding, etc. will still work. Much better!

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

Route::post('login', App\Http\Controllers\Api\V1\LoginController::class);

Route::middleware(['auth:api'])->prefix('v1')->group(function () {
    Route::post('file', App\Http\Controllers\Api\V1\FileUploadController::class);
});
```

**TL;DR**:

```diff
 <?php
 
+use Illuminate\Http\Request;
+use Illuminate\Support\Facades\Route;
 
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
 
-Route::post('login', 'LoginController@login');
+Route::post('login', App\Http\Controllers\Api\V1\LoginController::class);
 
 Route::middleware(['auth:api'])->prefix('v1')->group(function () {
-    Route::post('file', 'FileUploadController@upload');
+    Route::post('file', App\Http\Controllers\Api\V1\FileUploadController::class);
 });
```
