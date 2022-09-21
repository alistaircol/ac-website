---
title: "Create screenshots for all tailwind breakpoints using puppeteer with redis and bull queue"
author: "Ally"
summary: "Create screenshots for a list of pages at all tailwind breakpoints using puppeteer, and a queue producer and consumer with bull using a redis backing store."
publishDate: 2022-09-12T17:37:36+0100
tags: ['tailwind','puppeteer','bull','redis']
draft: true
---

I have recently spent some time making this website more responsive.

I was also working on a project which involved creating charts and saving them as image files to include in CMS content.

These ideas collided into this project, in which I take an rss feed of all my articles, run them through puppeteer at all tailwind breakpoints to see if there's any parts of the pages that look like they nede some attention.

## Puppeteer

I use puppeteer because I don't need to do any interaction on the page.

## Breakpoints

## Synchronous Implementation

## Bull

## Redis

## Bull Producer

## Bull Consumer
