---
title: "UK place data - a database as a Docker image, with a pointless multi-stage build to transform and load data"
author: "Ally"
summary: "A UK place name gazetteer loaded into a `docker` image with some spatial querying."
publishDate: 2020-12-13T12:00:00+01:00
tags: ['mysql', 'docker']
draft: false
---

## Introduction

Slightly related to a [previous article](https://ac93.uk/articles/publish-database-container-with-structure-and-data-for-ci/), which was my first dive into building and publishing custom docker images.

I bought a [data-set](https://www.gazetteer.org.uk/) of UK places years ago and never really did anything with it.

![Data](/img/articles/gazetteer/02-dataset.png)

In this post I will detail how I extract the data from the source CSV, transform the data very slightly to construct a target CSV, and finally load the data into a database. After all of that I will give a brief example of how this data could be used to calculate 'as the crow flies' distances between two points.

<center>

![Structure](/img/articles/gazetteer/01-structure.png)

</center>

## `Dockerfile`

Only the bottom part is relevant. It doesn't *need* a stage prior, but when learning that's what I did. I now learned that there's better tools than using PHP and a composer package to slightly transform the source data.

```dockerfile {hl_lines=[15]}
FROM php:7.4-cli as builder
COPY --from=composer:1.10 /usr/bin/composer /usr/bin/composer
COPY . /app

RUN apt-get update && \
    apt-get install -y git zip unzip libzip-dev && \
    docker-php-ext-configure zip && \
    docker-php-ext-install zip && \
    rm -rf /var/lib/apt/lists/partial && rm -rf /var/lib/apt/lists/* && \
    chmod +x /app/gazetteer

WORKDIR /app
ENV COMPOSER_AUTH='{"github-oauth": {"github.com": "redacted"}}'
RUN composer require league/csv
RUN ./gazetteer

# ---

FROM mysql:8.0
COPY --from=builder /app/output.csv /var/lib/mysql-files/gazetteer.csv
COPY structure.sql /docker-entrypoint-initdb.d/00-structure.sql
COPY import.sql /docker-entrypoint-initdb.d/01-import.sql
# --local-infile=1

# https://github.com/mysql/mysql-docker/blob/mysql-server/8.0/Dockerfile
# unquoted path is important
# [Note] [Entrypoint]: Starting temporary server
#mysqld: Error on realpath() on ''/var/lib/mysql-files'' (Error 2 - No such file or directory)
CMD ["mysqld", "--local-infile=1", "--secure-file-priv=/var/lib/mysql-files"]
```

The `./gazetteer` script is performing the transform part of the build. This is a simple PHP script
which forms part of the multi-stage build and isn't really required. A much simpler bash script does the job.

## Building

Building the image will require a few steps.

### Extract

I won't be able to distribute the csv, but the script will require the input in the format which is given from the download.

```text
head -n1 Gazetteer_201407.csv
Place Name,Grid Reference,Latitude,Longitude,County,Admin County,District,Unitary Authority,Police Area,Country
```

Since I'm not a masochist, having spaces in column names is a no for me. We'll transform these in the next step.

<center>

![no-spaces](/img/articles/gazetteer/no-spaces-in-column-names.jpg)

</center>


### Transform

For this, I wrote a fairly simple PHP script to transform the data slightly.

```php
#!/usr/bin/env php
<?php
require __DIR__ . '/vendor/autoload.php';

use League\Csv\Reader;
use League\Csv\Writer;

// input
$csv = Reader::createFromPath('/app/Gazetteer_201407.csv', 'r');
$csv->setHeaderOffset(0);

#$header = $csv->getHeader(); //returns the CSV header record
$records = $csv->getRecords();

$output = Writer::createFromPath('/app/output.csv', 'w');

$header = [
    'place_name',
    'grid_reference',
    'latitude',
    'longitude',
    'county',
    'administrative_county',
    'district',
    'unitary_authority',
    'police_area',
    'country',
];
$output->insertOne($header);
foreach ($records as $k => $record) {
    $output->insertOne([
        'id' => 100000 + $k, // annoyingly the local infile thing doesn't add auto increment thing itself
        'place_name' => $record['Place Name'],
        'grid_reference' => $record['Grid Reference'],
        'latitude' => $record['Latitude'],
        'longitude' => $record['Longitude'],
        'county' => $record['County'],
        'administrative_county' => $record['Admin County'],
        'district' => $record['District'],
        'unitary_authority' => $record['Unitary Authority'],
        'police_area' => $record['Police Area'],
        'country' => $record['Country'],
    ]);
}
```

But, I think we can do better.

```bash
echo 'id,place_name,grid_reference,latitude,longitude,county,administrative_county,district,unitary_authority,police_area,country' > output.csv
```

Need to increment the number of lines by 100,000 to give place names a consistent length ID.

```bash
csvtool drop 1 Gazetteer_201407.csv | awk '{print NR+100000  "," $s}' > output.csv
```

Now we don't really need the 'multi-stage build' part of it. Oh well.

### Load

There are a few steps to load the data, but all in a couple of `.sql` scripts.

#### Structure

First, will start off with the structure of the database.

Everything is relatively straightforward.

`structure.sql`:

```sql {linenos=true,hl_lines=[10,11]}
SET GLOBAL local_infile=1;

DROP SCHEMA IF EXISTS `gazetteer`;
CREATE SCHEMA IF NOT EXISTS `gazetteer` DEFAULT CHARACTER SET utf8mb4;

CREATE TABLE `gazetteer`.`uk_places` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `place_name` varchar(255) NOT NULL,
  `grid_reference` varchar(15) NOT NULL,
  `latitude` decimal(11,8) NOT NULL,
  `longitude` decimal(11,8) NOT NULL,
  `county` varchar(255) NOT NULL,
  `administrative_county` varchar(255) DEFAULT NULL,
  `district` varchar(255) DEFAULT NULL,
  `unitary_authority` varchar(255) DEFAULT NULL,
  `police_area` varchar(255) DEFAULT NULL,
  `country` varchar(10) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_place_name` (`place_name`),
  KEY `index_county` (`county`)
) ENGINE=InnoDB AUTO_INCREMENT=100000 DEFAULT CHARSET=utf8mb4;

use `gazetteer`
```

* `latitude` and `longitude` are stored as `decimal(11,8)` - this is gives us 8 places after decimal point, which is the highest resolution this data-set provides.
    * Later on we will add an additional column for better distance calculations between two poitns.

#### Import

`import.sql`:

```sql {hl_lines=[1,6]}
load data infile '/var/lib/mysql-files/gazetteer.csv'
into table uk_places
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;
```

The path is important, we start the container with the flag `--secure-file-priv` with this path `/var/lib/mysql-files`, so we can load the data from this file.

#### Cleansing

Now, the empty columns are interpreted as an empty string. The [way](https://stackoverflow.com/a/2675493/5873008) for the `load data infile` command to interpret these as null is `\N`.

```sql
update uk_places set administrative_county = null where administrative_county = '';
update uk_places set district = null where district = '';
update uk_places set unitary_authority = null where unitary_authority = '';
```

#### Adding `POINT` column

For better performance and easier calculations, we will add a new column to the table.

```sql
alter table uk_places add latitude_longitude point null;
```

#### Setting `POINT` data

Now setting the values:

```sql {hl_lines=[2]}
update uk_places
set latitude_longitude = st_srid(point(longitude, latitude), 4326)
where true;
```

Using `set_srid` will give the index we add later better performance. [Note order of coordinates](https://stackoverflow.com/a/42183467/5873008).

We will update the column to `not null`, can't add an index without that!

```sql
alter table uk_places modify latitude_longitude point not null;
```

#### `POINT` index

```sql
create index uk_places_latitude_longitude_index on uk_places (latitude_longitude);
```

## Query Usage

Using [`st_distance_sphere`](https://dev.mysql.com/doc/refman/8.0/en/spatial-convenience-functions.html#function_st-distance-sphere) between the two points will give you the distance in meters.

```sql
select st_distance_sphere(
    (select latitude_longitude from uk_places where id = 117854), # glasgow
    (select latitude_longitude from uk_places where id = 127889)  # london
) as 'distance_in_m'
from dual;
```

Result:

```text
554522.8318811639
```

![Glasgow to London](/img/articles/gazetteer/09-glasgow-london.png)

## Building Image

I won't go in to too much detail here. I went into more detail in my previous article [here](https://ac93.uk/articles/publish-database-container-with-structure-and-data-for-ci/) including publishing to registry, etc.

I'll just leave a `Makefile` which might have some issues.

```makefile
.PHONY: rmi build
.ONESHELL:
# https://www.gnu.org/software/make/manual/make.html#Errors
# keeps going on error, i.e. if no image was removed, it's not the end of the world for the build stage :)
.IGNORE:

rmi:
	docker image rm --force $$(docker image ls -a -q --filter reference=gazetteer) 2>/dev/null

build:
	docker build --force-rm --tag=gazetteer:latest --tag=gazetteer:2014-07 .

down:
	docker container stop $$(docker container ls -a -q --filter name=db_gazetteer) 2>/dev/null

server: down
	docker run --rm -p 3333:3306 --name db_gazetteer -e MYSQL_ROOT_PASSWORD=password gazetteer:latest

image:
	docker image ls -a --filter reference=gazetteer

container:
	docker container ls -a -q --filter name=db_gazetteer

shell:
	docker run -it gazetteer:latest bash
```

In the future, I might add a [basic application](https://symfony.com/doc/current/components/console/helpers/questionhelper.html#autocompletion) around this.
