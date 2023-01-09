---
title: Build a simple PHP contact form using Google Cloud Function PHP and deploy code with GitHub action"
author: "Ally"
summary: "Create a simple contact form using Google Cloud Function PHP runtime to send an email from a contact form. The contact form will have CI to deploy the source to the GCF and invoke another repository to update the GCF API URI."
publishDate: 2023-01-03T19:09:23+01:00
tags: ['php', 'gcp', 'ci']
draft: true
---

This post will outline how I will create a serverless contact form with a PHP runtime in GCP which is built as a small component in an arbitrary website.

This will mainly involve three repositories:

* [![gcf-website](https://img.shields.io/badge/alistaircol/gcf--website-alpine.js-8BC0D0?style=flat&logo=alpine.js)](https://github.com/alistaircol/gcf-website)
* [![gcf-contact-form](https://img.shields.io/badge/alistaircol/gcf--contact--form-php-777BB4?style=flat&logo=php)](https://github.com/alistaircol/gcf-contact-form) ![You are here](https://img.shields.io/badge/-you%20are%20here-brightgreen)
* [![gcf-contact-form-infrastructure](https://img.shields.io/badge/alistaircol/gcf--contact--form--infrastructure-terraform-7B42BC?style=flat&logo=terraform)](https://github.com/alistaircol/gcf-contact-form-infrastructure)

* `contact-form-website`: A static site for which a contact form is required.
* `contact-form-infrastructure`: Terraform scripts to create relevant GCP infrastructure
* `contact-form`: A relatively simple PHP script to validate form request, and send an email. Will also have CI to:
  * Create code bundle and upload to GCP function

TBD if the GCP function URI will change after code refresh, if so some CI may be required to update the `website`.

## Setting up GCP provider

```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.47.0"
    }
  }
}

provider "google" {
  # Configuration options
}
```

TBD: [how the token is stored and how it's configured](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference)

## Create a GCP Bucket for our code

```hcl
resource "google_storage_bucket" "function_contact_form_general" {
  name     = "contact_form_general"
  location = "us-central1"
}
```

TBD: [location of bucket to be UK](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket)

TBD: the location can be configured in the provider, probably use a variable.

## Create a GCP Function

```hcl
resource "google_cloudfunctions_function" "contact_form_general" {
  name                  = "contact_form_general"
  runtime               = "php81"
  entry_point           = "submitForm"
  source_archive_bucket = google_storage_bucket.function_contact_form_general.name
  source_archive_object = "source.zip"
  trigger_http          = true
  memory_size           = 256
  timeout               = 60
  environment_variables = {
    "SMTP2GO_TOKEN" = var.smtp2go_token
  }
}
```

TODO: create SMTP2GO token variable in and setup `.tfvars.example`

## Implementing the contact form

Create a new `contact-form` project by starting with GCF framework.

```bash
mkdir contact-form && cd contact-form
docker run \
    --rm \
    --tty \
    --interactive \
    --volume="$(pwd):/app" \
    --volume="${COMPOSER_HOME:-$HOME/.composer}:/tmp" \
    --workdir=/app \
    thecodingmachine/php:8.1-v4-cli \
    composer --no-interaction init \
    --name="alistaircol/gcf-contact-form" \
    --description="Ally's contact form running in GCF" \
    --author="Ally" \
    --type="project" \
    --homepage="https://ac93.uk/articles/gcp-gfc-php-function-as-contact-form-api-with-ci/" \
    --require="google/cloud-functions-framework:^1.0"
    
docker run \
    --rm \
    --tty \
    --interactive \
    --volume="$(pwd):/app" \
    --volume="${COMPOSER_HOME:-$HOME/.composer}:/tmp" \
    --workdir=/app \
    thecodingmachine/php:8.1-v4-cli \
    composer install
```

`composer.json`:

```json
{
    "name": "alistaircol/gcf-contact-form",
    "description": "Ally's contact form running in GCF",
    "type": "project",
    "homepage": "https://ac93.uk/articles/gcp-gfc-php-function-as-contact-form-api-with-ci/",
    "require": {
        "google/cloud-functions-framework": "^1.0"
    },
    "authors": [
        {
            "name": "Ally"
        }
    ]
}
```

Update the PHP target version in `composer.json` some `scripts` as per some GCP code [samples](https://github.com/GoogleCloudPlatform/php-docs-samples/blob/4126e730880bac8bf77dfd625e698cdec719df14/functions/http_form_data/index.php).

`FUNCTION_TARGET` here is the `google_cloudfunctions_function.contact_form_general.entryPoint`.

```json
{
    "name": "alistaircol/gcf-contact-form",
    "description": "Ally's contact form running in GCF",
    "type": "project",
    "homepage": "https://ac93.uk/articles/gcp-gfc-php-function-as-contact-form-api-with-ci/",
    "require": {
        "php": "^8.1",
        "google/cloud-functions-framework": "^1.0"
    },
    "authors": [
        {
            "name": "Ally"
        }
    ],
    "scripts": {
        "start": [
            "Composer\\Config::disableProcessTimeout",
            "FUNCTION_TARGET=submitForm php -S localhost:${PORT:-8080} vendor/google/cloud-functions-framework/router.php"
        ]
    }
}
```
