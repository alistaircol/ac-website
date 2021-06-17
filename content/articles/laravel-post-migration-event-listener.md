---
title: "Laravel post migration event listener"
author: "Ally"
summary: "Want your Laravel app to do something after running migrations? Here's how I did it."
publishDate: 2021-06-17T19:16:55+0100
tags: ['laravel','event','migration','post-migration']
draft: false
---

I work on a few different Laravel applications using the same database between them.

Only one of the applications has migrations, and the others have models linked to the singular database.

---

When I run migrations on the project containing the migration files, I have to run my script to generate the `laravel-ide-helper` files for *each* project and sometimes I may have forgotten to run this after running a migration, causing some *Argh* moments.

How do you listen to a post-migration event?

There's nothing out of the box for this, but I'll show what I did.

- Make a service provider
- Register the service provider
- Make a post-migration handler

## Service Provider

I'm not 100% sure whether this is the best approach, but I want to dump this information here.

While trying to find a solution, I answered [this](https://stackoverflow.com/questions/63194721) similar SO question.

```bash
php artisan make:provider CommandListenerProvider
```

Will unsurprisingly generate `app/Providers/CommandListenerProvider.php`.

```diff
 <?php
 
 namespace App\Providers;
 
 use Event;
 use Illuminate\Console\Events\CommandStarting;
 use Illuminate\Database\Events\MigrationsEnded;
 use Illuminate\Support\ServiceProvider;
 
 class CommandListenerProvider extends ServiceProvider
 {
     public $isPretend = true;
     
     /**
      * Register services.
      *
      * @return void
      */
     public function register()
     {
         //
     }
     
     public function boot()
     {
+         Event::listen(CommandStarting::class, function (CommandStarting $event) {
+             if ($event->input->hasParameterOption('migrate')
+                 && !$event->input->hasParameterOption('--pretend')
+             ) {
+                 $this->isPretend = false;
+             }
+         });
+
+         Event::listen(MigrationsEnded::class, function (MigrationsEnded $event) {
+             if ($this->isPretend) {
+                 return;
+             }
+             // TODO: whatever you want post-checkout :)
+         });
     }
 }
```

## Register the Service Provider

Really easy, just add to `config/app.php`:

```diff
     /*
     |--------------------------------------------------------------------------
     | Autoloaded Service Providers
     |--------------------------------------------------------------------------
     |
     | The service providers listed here will be automatically loaded on the
     | request to your application. Feel free to add your own services to
     | this array to grant expanded functionality to your applications.
     |
     */
     'providers' => [
         /*
          * Laravel Framework Service Providers...
          */
         // truncated
         
         /*
          * Package Service Providers...
          */
          
         /*
          * Application Service Providers...
          */
         App\Providers\AppServiceProvider::class,
         App\Providers\AuthServiceProvider::class,
         // App\Providers\BroadcastServiceProvider::class,
         App\Providers\EventServiceProvider::class,
         App\Providers\RouteServiceProvider::class,
+        App\Providers\CommandListenerProvider::class,
     ],
```

## Post-Migration handler

You can do whatever you want, but for me, I want to generate `laravel-ide-helper` files.

I've implemented the `TODO: whatever you want post-checkout :)` simply to run this `post-checkout` target in the repository containing the migrations `Makefile`.

```makefile
post-checkout: website1 website2 website3

ide_helper = composer require barryvdh/laravel-ide-helper ^2.7; \
	php artisan ide-helper:meta; \
	php artisan ide-helper:generate --helpers; \
	php artisan ide-helper:eloquent; \
	php artisan ide-helper:models --nowrite; \
	git restore composer.json composer.lock

website1:
	cd ~/development/website1
	${ide_helper}
	
website2:
	cd ~/development/website2
	${ide_helper}
	
website3:
	cd ~/development/website3
	${ide_helper}
```
