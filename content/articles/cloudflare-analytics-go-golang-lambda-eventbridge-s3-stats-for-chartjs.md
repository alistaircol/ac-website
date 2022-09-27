---
title: "Save Cloudflare analytics in a S3 bucket with a Golang Lambda and Eventrbidge"
summary: "Save analytics from Cloudflare's graphql API using a Golang Lambda function into a S3 bucket on a schedule with Eventbridge, eventually rendering with chartjs."
author: "Ally"
publishDate: 2022-09-27T19:54:27+01:00
tags: ['go', 'aws', 'lambda', 's3', 'eventbridge', 'cloudflare']
draft: true
---

{{<github-repository url="https://github.com/alistaircol/go-cloudflare-graphql-analytics" repository="alistaircol/go-cloudflare-graphql-analytics" title="Explore full repository">}}

Terraform scripts for this may come later.

## Lambdas

Create three lambda functions:

* `blog-analytics-1d`
* `blog-analytics-1w`
* `blog-analytics-1m`

This will create relevant roles with policies. The Lambda will need some additional policy changes later on to put files in the bucket.

## S3

* Create an S3 bucket with static website hosting enabled
* Make sure public access is enabled
* There will also need to be a policy update on the bucket:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicRead",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::ac93-blog-analytics/*",
            "Condition": {
                "NotIpAddress": {
                    "aws:SourceIp": [
                        "1.1.1.1"
                    ]
                }
            }
        }
    ]
}
```

Attach the CORS policy:

```json
[
  {
    "AllowedHeaders": [],
    "AllowedMethods": [
      "GET"
    ],
    "AllowedOrigins": [
      "*"
    ],
    "ExposeHeaders": []
  }
]
```

## S3 Policy

Go to IAM and create a new policy we will attach to the Lambda function, and to a new programmatic user for testing locally.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::ac93-blog-analytics/*"
        }
    ]
}
```

## Lambda S3 Policy

Go to IAM and then Roles, when you created the Lambda functions earlier it will have created the role which we can update to give access for the Lambda to the S3 bucket.

## Optional: API user with S3 access

This is only required for local testing, when code is executing in Lambda there will be `AWS_ACCESS_KEY_ID`, `AWS_SECRET_KEY` and `AWS_REGION` in the environment.

Go to IAM and create a new user with programmatic access and attach the same S3 profile.

```bash
aws configure --profile=blog-analytics
```

or just set the environment variables.

## Lambda Code

```bash
task dist
```

Then upload files to each lambda function, and add the following environment variables:

```text
AWS_S3_BUCKET=
CLOUDFLARE_ZONE=
CLOUDFLARE_EMAIL=
CLOUDFLARE_TOKEN=
```

## Eventbridge

Create two rules, with the Lambdas as targets.
