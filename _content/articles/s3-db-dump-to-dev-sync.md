---
title: "S3 Database Dump Sync For Local Development"
author: "Ally"
summary: "A simple `whiptail` script to select which databases you want to refresh for local development work. Downloads using `awscli` and some `pv` for progress on decompressing and importing."
publishDate: 2020-07-16T12:00:00+01:00
tags: ['aws', 's3', 'bash', 'whiptail']
draft: false
---

For better or worse, we download a backup of production database (`mysqldump` in a lambda, but that's not important) and import it into our local development machine.

Using `awscli` for downloading the dump from the bucket.

* `pip3 install --user awscli`

Make sure you have `whiptail` and `pv`.

---

Set up profile as per `awscli` recommendations:

`~/.aws/credentials`:

```text
[ac-app-production]
aws_access_key_id = YOUR_KEY
aws_secret_access_key = YOUR_SECRET
region = eu-west-1
```

---

The summary:

* Lambda puts the compressed single file of the entire database into a s3 bucket
* Download `.sql.gz`
* Extract `.sql.gz`
* Import `.sql`

![screenshot](/img/articles/s3-db-dump-sync/screenshot.png)

```shell script
#!/usr/bin/env bash
# files downloaded from S3 go here
OUT="$HOME/development/databases"
BUCKET_NAME="ac-app-database-dumps"

# databases available to us
DATABASES="$(whiptail \
  --title "Databases to sync" \
  --checklist \
  "Select the following databases you want locally to \be synced from $(date -d "yesterday 13:00" '+%d/%m/%Y') production database." \
  16 \
  48 \
  3 \
  "ac_crm" "ac_crm                  " OFF \
  "ac_mem" "ac_mem                  " OFF \
  "ac_aaa" "ac_aaa                  " OFF \
  3>&1 1>&2 2>&3
)"

for db in $DATABASES; do
  # remove quotes from db name that whiptail sends
  db_name=$(echo $db | tr -d '"')
  # get yesterdays date for latest db backup
  yesterday=$(date -d "today 13:00" '+%Y-%m-%d')
  # download dump to specified folder
  aws s3 --profile=ac-app-production \
    cp \
    s3://$BUCKET_NAME/$db_name-$yesterday.sql.gz \
    $OUT/$db_name.sql.gz  
  # extract dump
  pv $OUT/$db_name.sql.gz \
    | gunzip \
      --keep \
      --force \
      --decompress \
      > $OUT/$db_name.sql
  # import dump
  pv $OUT/$db_name.sql \
    | mysql \
      --port=3396 \
      --host=127.0.0.1 \
      --user=root \
      --password=password \
      $db_name
done
```


A couple things to note using `mysql` on the machine for the import (this runs as a docker container):

* Port is 3396 where 3306 is standard for `mysql`, this is the docker port mapping, 3396 is public port outside the docker network
* I'd use the `mysql` running inside database container for doing the import like below, but it's much slower

```shell script
pv $OUT/$db_name.sql \
  | docker exec \
    --interactive \
    ac_db \
    bash -c "mysql --user=root --password=password $db_name" \
    2> /dev/null
```
