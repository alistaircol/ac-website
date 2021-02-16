---
title: "A backend implementation for livewire/sortable"
author: "Ally"
summary: "How to handle backend requests given from `livewire/sortable`. Data fetched in mount - think `Post`s by `User`s (as prop into Livewire component) under a `Category` (as prop into Livewire component), then sort order persisted during action and re-rendered seamlessly."
publishDate: 2021-02-16T00:00:00+01:00
tags: ['php', 'laravel', 'livewire']
draft: false
---

I recently was frustrated by the lack of documentation on the in the [`livewire/sortable`](https://github.com/livewire/sortable#usage) package when it comes to handling the backend persistence of the new sort order.

Usage on a blade page:

```html
<livewire:sort-order :user="$user" :category="$category" />
```

Basically our component will take input of a user and category. The component will then gather posts from that user within/underneath the category (the implementation detail for this is unimportant).

The Livewire component:

`resources/views/livewire/sort-order.blade.php`

```html
<div>
    {{-- Close your eyes. Count to one. That is how long forever feels. --}}

     <table>
        <thead>
            ...
        </thead>
        <tbody wire:sortable="changeSortOrder">
        @foreach($posts as $post)
            <tr wire:sortable.item="{{ $option->id }}"
                wire:key="{{ $option->id }}"
            >
                <td>
                    <x.icons.heroicons.handle
                        class="w-6 h-6 inline"
                        wire:sortable.handle
                    />
                    &nbsp;{!! Str::title($post->title) !!}
                </td>
                ...
            </tr>
        @endforeach
        </tbody>
    </table>
 </div>
```


The Livewire component:

`app\Http\Livewire\SortOrder.php`

```php
<?php

namespace App\Http\Livewire;

use Livewire\Component;
use Illuminate\Support\Collection;
use App\Models\Posts;

class SortOrder extends Component
{
    public $user;
    public $category;

     /**
     * @var Collection
     */
    public $posts;

    public function mount($user, $category)
    {
        $this->user = $user;
        $this->category = $category;
        // just for the initial load
        $this->buildOptions = Posts::getPostsFromUserWithinCategory(
            $this->user,
            $this->category
        );
    }

    public function render()
    {
        return view('livewire.sort-order');
    }

     /**
     * Array of tuples (array) come in format (in my case):
     * ['value' => model_id, 'order' => order from front-end]
     * Check your component wires :)
     *
     * @param  array  $sortOrderBuildOptionIdTuples
     */
    public function changeSortOrder(array $sortOrderuples)
    {
        $tuples = collect($sortOrderuples);

        // $this->posts->transform(...) is meant to edit in place
        // I couldn't make livewire recognise any changes by this method
        $posts = $this->posts
            ->map(function (Post $post) use ($tuples) {
                $tuple = $tuples->where('value', (int) $post->id)->first();
                $option->update(['sort_order' => (int) $tuple['order']]);
                return $option->fresh();
            })
            ->sortBy('sort_order');

         $this->hydratePosts($posts);
    }

    /**
     * Doesn't think it's been updated if done within changeSortOrder..
     *
     * @param  Collection  $posts
     */
    private function hydratePosts(Collection $posts)
    {
        // having the $this->posts->each/transform do update
        // and then assigning posts like in the mount here doesn't work either
        $this->posts = $posts;
    }
}
```

I'm new to Livewire too, so this was harder than it perhaps ought to have been.

**Disclaimer**: this might be terrible, but it's more for my reference than anything!

This works without rendering twice after many hours of trial and error. It's really slick and so happy to get an implementation working, and I'm sure I'll refer back to it and hopefully this could help some other poor soul.

**TODO**: maybe get some logs showing execution order with/without call to hydrate manually.
