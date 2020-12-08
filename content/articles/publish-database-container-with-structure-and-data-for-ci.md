---
title: "Creating a private Docker container with database structure and data for CI"
author: "Ally"
summary: "Building a private Docker container with custom structure and data for legacy apps for a slightly easier CI pipeline"
publishDate: 2020-12-08T12:00:00+01:00
tags: ['mysql', 'docker', 'ci']
draft: true
---

**Rationale**: Application is quite old and is *very* database heavy in its testing and is unfeasible for it to be changed.
This has made the testing of this application quite cumbersome - involving a script to pull the structure of all tables,
and certain other data tables where it's too much for fixture data. Extracting this data to sqlite database too is a
possibility but might cause different issues.

The applications framework has a [plugin](https://github.com/lorenzo/cakephp-fixturize) which can load [fixture](https://phpunit.readthedocs.io/en/9.3/fixtures.html) data from a database table, which is ideal for the applications use-case. Though others will load fixture data from a CSV.

The framework does all its testing in a schema predictably called `testing`.
 
The test cases `setUpBeforeClass` will behind-the-scenes copy any structure from fixtures (from the `testing_fixtures` schema) and populate from `testing_fixtures` if configured, else from a csv, or no data.

<center>

![fixtures](/img/articles/docker-db-ci/fixtures.png)

</center>

---

A script, possibly something like [this](https://gist.github.com/alistaircol/7dac533f056cec38cd19b2571a52e4a0) which will use `mysqldump` to dump structure of schemas, and certain tables data for import later, to help test suite run, will create an output file, `crm.sql`.

This whole process of building the `crm.sql` file and the `docker image` might be best done inside a lambda/serverless part of infrastructure where the database is being hosted, but that's too out of scope for this humble tutorial.

Creation of this file is a pre-requisite to building the new image.

---

Building the new image with the structure is pretty easy once this file has been generated.

The `Dockerfile` could look something like below.

```dockerfile {hl_lines=[4,5,6,7]}
FROM mysql:5.7
COPY crm.sql /tmp/crm.sql
RUN touch /tmp/crm-header.sql \
 && echo 'create schema if not exists testing;' > /tmp/crm-header.sql \
 && echo 'create schema if not exists testing_fixtures;' > /tmp/crm-header.sql \
 && echo 'use testing_fixtures;' >> /tmp/crm-header.sql \
 && cat /tmp/crm-header.sql /tmp/crm.sql > /docker-entrypoint-initdb.d/crm.sql
```

* `testing` is `drop`ped and `create`d in the frameworks testing runner
* `testing_fixtures` is pretty much a read-only holding area, the frameworks testing runner will use this as a reference for structure and data for each test case 
* `use testing_fixtures;` since the dump script doesn't have any awareness of that

Building the image:

```bash
docker build -f DockerfileDbCi -t alistaircol/db-ci .
```

Testing the image contains fixture data, etc.:

```bash
docker container rm -f $(docker container ls -a -q --filter name=db_ci) 2>/dev/null
docker run --rm -d -p 3333:3306 --name db_ci -e MYSQL_ROOT_PASSWORD=password db_ci:latest
```

Publishing the image:

```bash
docker login --username=alistaircol

Password: 
WARNING! Your password will be stored unencrypted in /home/ally/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store
Login Succeeded
```
