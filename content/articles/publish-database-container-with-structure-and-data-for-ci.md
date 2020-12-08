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

---

Need to `mysqldump` structure of schemas, and certain tables data.

```bash
#!/usr/bin/env bash

# --column-statistics=0: https://serverfault.com/a/912677/530593
DUMP_COMMAND="mysqldump \
    --column-statistics=0
    --host=db.ac93.uk \
    --user=user \
    --password=password"

function dump_crm_structure()
{
    # when dumping crm structure, ignore this table
    IGNORE_CRM_TABLES=(
        "ignore_1"
    )
    CRM_STRUCTURE="$DUMP_COMMAND \
        ac_crm \
        --no-data \
        --skip-triggers"

    for table in ${IGNORE_CRM_TABLES[*]}; do
        CRM_STRUCTURE+="\
        --ignore-table=ac93_crm.$table"
    done

    $CRM_STRUCTURE >> crm.sql
}

function dump_crm_data()
{
    # when dumping data, only use these tables
    DATA_CRM_TABLES=(
        "allow_1"
    )
    CRM_DATA="$DUMP_COMMAND \
        ac_crm \
        --no-create-info \
        --skip-triggers \
        ${DATA_CRM_TABLES[*]}"

    $CRM_DATA >> crm.sql
}

# dump only these internal tables and data
DATA_INTERNAL_TABLES=(
    "allow_1"
)

function dump_internal_structure
{
    INTERNAL_STRUCTURE="$DUMP_COMMAND \
        --no-data \
        ac93_internal \
        ${DATA_INTERNAL_TABLES[*]}"

    $INTERNAL_STRUCTURE >> crm.sql
}

function dump_internal_data
{
    INTERNAL_DATA="$DUMP_COMMAND \
        --no-create-info \
        --skip-triggers \
        ac93_internal \
        ${DATA_INTERNAL_TABLES[*]}"

    $INTERNAL_DATA >> crm.sql
}

rm crm.sql
dump_crm_structure
dump_crm_data
dump_internal_structure
dump_internal_data
echo "Done!"
```

Will create `crm.sql` - a pre-requisite to building the new image.

```dockerfile
FROM mysql:5.7
# run cpt.sh prior to this - it's required to be ran from the host machine!
COPY crm.sql /tmp/crm.sql
RUN touch /tmp/crm-header.sql \
 && echo 'create schema if not exists testing;' > /tmp/crm-header.sql \
 && echo 'use testing;' >> /tmp/crm-header.sql \
 && cat /tmp/crm-header.sql /tmp/crm.sql > /docker-entrypoint-initdb.d/crm.sql
```

Building the image:

```
docker container stop $(docker container ls -a -q --filter name=qa_db_ci)
docker container rm $(docker container ls -a -q --filter name=qa_db_ci)
docker build -f DockerfileDbCi -t qa_db_ci .
# push
docker run -p 3333:3306 --name qa_db_ci -e MYSQL_ROOT_PASSWORD=password qa_db_ci:latest #add -d for daemon/detached shit

```

Publishing the image:

```bash
docker build -f DockerfileDbCi -t alistaircol/qa-db-ci .

docker login --username=alistaircol

Password: 
WARNING! Your password will be stored unencrypted in /home/ally/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store
Login Succeeded
```

TODO: screenshot

TODO: pipeline
