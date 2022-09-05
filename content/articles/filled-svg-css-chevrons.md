---
title: "Making filled triangle SVG with CSS"
author: "Ally"
summary: "Understanding basic SVG `path` and `viewbox` for a simple filled triangle."
publishDate: 2021-05-18T22:00:56+0100
tags: ['css', 'svg']
draft: false
---

<center>

![alt](/img/articles/svg-triangles/meme.png)

</center>

SVG's have been a bit of a mystery to me, and some design work meant I had to get familiar with the basics.

I came up with these amazing pieces of art:

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 16 4" fill="currentColor">
  <title>Down</title>
  <path d="M0 0 L8 4 L16 0"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 16 4" fill="currentColor">
  <title>Up</title>
  <path d="M0 4 L8 0 L16 4"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 4 16" fill="currentColor">
  <title>Right</title>
  <path d="M0 0 L4 8 L0 16"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 4 16" fill="currentColor">
  <title>Left</title>
  <path d="M4 0 L0 8 L4 16"/>
</svg>

Why? Design required an aesthetic like this:

<p class="codepen" data-height="265" data-theme-id="dark" data-default-tab="html,result" data-user="alistaircol" data-slug-hash="JjWbYXQ" style="height: 265px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border: 2px solid; margin: 1em 0; padding: 1em;" data-pen-title="SVG Triangle: Design">
  <span>See the Pen <a href="https://codepen.io/alistaircol/pen/JjWbYXQ">
  SVG Triangle: Design</a> by Ally (<a href="https://codepen.io/alistaircol">@alistaircol</a>)
  on <a href="https://codepen.io">CodePen</a>.</span>
</p>

## Explanation

<p class="codepen" data-height="265" data-theme-id="dark" data-default-tab="html,result" data-user="alistaircol" data-slug-hash="NWpbGKg" style="height: 265px; box-sizing: border-box; display: flex; align-items: center; justify-content: center; border: 2px solid; margin: 1em 0; padding: 1em;" data-pen-title="SVG triangle: Facing down">
  <span>See the Pen <a href="https://codepen.io/alistaircol/pen/NWpbGKg">
  SVG triangle: Facing down</a> by Ally (<a href="https://codepen.io/alistaircol">@alistaircol</a>)
  on <a href="https://codepen.io">CodePen</a>.</span>
</p>

[`viewBox`](https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/viewBox) is an attribute that goes on the `svg`

* `min x` of the svg viewport - `0` in our case - none of our points/lines x co-ordinate goes negative
* `min y` of the svg viewport - `0` in our case - none of our points/lines y co-ordinate goes negative
* `width` - width of the svg viewport - `16` in our case, our maximum x point is `16`
* `height` - height of our svg viewport - `4` in our case, our maximum y point is `4`

[`path`](https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths) is an element within an `svg` element.

There can be may `path` elements, but in our simple triangle the `path` is defined by the [`d`](https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/d) parameter - the path to be drawn.

Our path is very simple:

* `M0,0` means [move to](https://svgwg.org/specs/paths/#PathDataBNF) (0, 0)
* `L8,4` means [line to](https://svgwg.org/specs/paths/#PathDataBNF) (8, 4) from the last point (0, 0) - the blue line in diagram below
* `L16,0` means [line to](https://svgwg.org/specs/paths/#PathDataBNF) (16, 0) from the last point (8, 4) - the red line in diagram below

I always find a diagram helps (it's not 100% accurate, but close enough):

<center>

![Graph](/img/articles/svg-triangles/plotting.svg)

</center>

For the rest of the orientations, it's just a case of changing the `path`'s `d` co-ordinates, and the `viewBox`.

---

## Code

Objects embedded at top on this page:

```html
<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 16 4" fill="currentColor">
  <title>Down</title>
  <path d="M0 0 L8 4 L16 0"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 16 4" fill="currentColor">
  <title>Up</title>
  <path d="M0 4 L8 0 L16 4"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 4 16" fill="currentColor">
  <title>Right</title>
  <path d="M0 0 L4 8 L0 16"/>
</svg>

<svg xmlns="http://www.w3.org/2000/svg" style="height: 32px; width: 32px; background-color: #1f2937; color: white" viewBox="0 0 4 16" fill="currentColor">
  <title>Left</title>
  <path d="M4 0 L0 8 L4 16"/>
</svg>
```

### Codepens

I've extracted the above objects into codepens too.

* [Design usage](https://codepen.io/alistaircol/pen/JjWbYXQ)
* [Facing down](https://codepen.io/alistaircol/pen/NWpbGKg)
* [Facing up](https://codepen.io/alistaircol/pen/WNpoQNE)
* [Facing left](https://codepen.io/alistaircol/pen/ExWNVxG)
* [Facing right](https://codepen.io/alistaircol/pen/JjWbYjV)

<script async src="https://cpwebassets.codepen.io/assets/embed/ei.js"></script>
