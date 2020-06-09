---
title: "API & Database Migration Strategy"
author: "Ally"
summary: "MySQL database replication where a new application becomes single source of truth but a legacy application still needs access to database. Or simply a strategy to allow 'cross-database' joins."
publishDate: 2020-06-08T12:00:00+01:00
tags: ['mysql']
draft: false
---

**TL;DR**:

* Incremental migration of features from legacy system to new platform.
* New platform will be the single source of truth, however legacy application still needs direct database access (read-only) to function while the long migration process is in progress.
* Legacy system has lots of data dependencies, so it's hard to identify them all and fix accordingly. Cross-database joins aren't really a thing.
* Set up database replication so legacy system has access to new platform data within same legacy system database.

---

We are developing a new (Symfony) codebase, incrementally migrating features from the old codebase (CakePHP 2.x).
Old project will still have dependencies which aren't going to be migrated since it's incremental instead of a big switchover.

* `New`: MariaDB 10
* `Old`: MySQL 8

Docker setup preamble is at the end of the article since it isn't the entire focus of this article.

This is covering local development as a proof of concept. For stage/production instructions, too bad! Maybe later.

---


`.db.main.cnf`:

```diff
[mysqld]
# These couple of options are just for docker stuff
# https://github.com/docker-library/mysql/issues/69#issuecomment-412177146
# https://github.com/docker-library/mysql/issues/541#issuecomment-463320181
# alternatively can be put in docker-compose like this:
# command: --innodb-use-native-aio=0 --secure-file-priv=NULL
innodb_use_native_aio = 0
secure-file-priv = ""

general_log = 1
general_log_file = /var/log/mysql/mysql.log

slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 5

log_error = /var/log/mysql/error.log

# server-id: Must be set to 0 for binary logging to take place
# Reference: https://dev.mysql.com/doc/refman/5.7/en/replication-options.html#option_mysqld_server-id
server-id = 0

# binlog-format: statement best fits our use-case
# Reference: https://dev.mysql.com/doc/refman/5.7/en/binary-log-formats.html
# Reference: https://dev.mysql.com/doc/refman/5.7/en/replication-options-binary-log.html#sysvar_binlog_format
binlog-format = STATEMENT

# expire_logs_days: Will keep binary logs for 7 days
# Reference: https://dev.mysql.com/doc/refman/5.7/en/replication-options-binary-log.html#sysvar_expire_logs_days
expire_logs_days = 7

# Reference: https://dev.mysql.com/doc/refman/5.7/en/replication-options-binary-log.html#option_mysqld_log-bin
log-bin = /var/lib/mysql/bin-log

# We only care about binary logs for one database
# Reference: https://dev.mysql.com/doc/refman/5.7/en/replication-options-binary-log.html#option_mysqld_binlog-do-db
binlog-do-db = core

```

`main.sql`:

Main should contain users and not notes.

```mysql
create user if not exists 'repl'@'%' identified with caching_sha2_password by 'repl_password';
grant replication slave on *.* to 'repl'@'%';
flush privileges;

drop schema if exists `core`;
create schema if not exists `core`;

create table core.notes
(
	id char(36) not null,
	note_id int auto_increment comment 'Display ID',
	content text null,
	user_id char(36) not null comment 'Author',
	created datetime default NOW() null,
	updated datetime default NOW() null,
	pinned datetime default NULL null,
	constraint notes_pk
		primary key (id),
	constraint notes_uniq
		unique (note_id)
);

INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6ad-566c-46a9-ab0e-0270c0a88004', 1, 'molestiae dolores nemo aliquam velit unde error perferendis minus officia ut tenetur vitae veniam eveniet eveniet quas', '5edba620-8ea8-4791-8d5b-01bcc0a88004', '2020-06-06 14:22:37', '2020-06-06 14:22:37', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6bf-99c4-4ac2-9953-027cc0a88004', 2, 'sapiente sunt rerum error aliquid veritatis harum sint maiores quo iusto', '5edba621-eff8-4481-b980-01c8c0a88004', '2020-06-06 14:22:55', '2020-06-06 14:22:55', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c0-402c-4c4f-a9bc-0288c0a88004', 3, 'et quia laboriosam in non recusandae cum enim adipisci molestiae aut est eius culpa qui perferendis distinctio qui aliquid inventore', '5edba620-8ea8-4791-8d5b-01bcc0a88004', '2020-06-06 14:22:56', '2020-06-06 14:22:56', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c0-0a20-4bbf-acb9-0294c0a88004', 4, 'id ipsam facere aut quibusdam nemo consequatur velit recusandae et', '5edba61e-1d6c-4483-a777-01b0c0a88004', '2020-06-06 14:22:56', '2020-06-06 14:22:56', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c1-5698-430a-8f51-02a0c0a88004', 5, 'quibusdam vitae est vero beatae recusandae molestiae ex ad nihil cupiditate neque earum quisquam blanditiis dolor qui reiciendis qui vero', '5edba620-8ea8-4791-8d5b-01bcc0a88004', '2020-06-06 14:22:57', '2020-06-06 14:22:57', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c1-9f30-4132-bc5e-02acc0a88004', 6, 'sunt enim dicta sequi quibusdam esse omnis provident quia quod neque ad quos officiis ut quae aut nihil nemo in', '5edba621-eff8-4481-b980-01c8c0a88004', '2020-06-06 14:22:57', '2020-06-06 14:22:57', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c1-2b9c-4318-94b4-02b8c0a88004', 7, 'nam officiis animi est sed laboriosam velit autem qui nam iure voluptates totam dignissimos ipsa', '5edba4be-b7b8-451b-8c63-018cc0a88004', '2020-06-06 14:22:57', '2020-06-06 14:22:57', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c2-4a60-4e03-abf2-02c4c0a88004', 8, 'est quos numquam ipsum est et numquam velit dicta voluptatem molestiae', '5edba620-8ea8-4791-8d5b-01bcc0a88004', '2020-06-06 14:22:58', '2020-06-06 14:22:58', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c2-f1a0-445e-8f6d-02d0c0a88004', 9, 'eos nihil ut nesciunt et excepturi alias quisquam ea distinctio libero laborum quis fuga', '5edba4be-b7b8-451b-8c63-018cc0a88004', '2020-06-06 14:22:58', '2020-06-06 14:22:58', null);
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)VALUES ('5edba6c2-c3a4-4d63-abb0-02dcc0a88004', 10, 'quas et quae suscipit mollitia id quasi ea vero quia et quibusdam tenetur autem ea inventore aliquid quis quia', '5edba61e-1d6c-4483-a777-01b0c0a88004', '2020-06-06 14:22:58', '2020-06-06 14:22:58', null);
```


`recore.sql`:

```mysql
drop schema if exists `recore`;
create schema if not exists `recore`;

create table recore.users
(
	id char(36) default UUID() not null,
	user_id int auto_increment comment 'Display field',
	first_name varchar(100) null,
	last_name varchar(100) null,
	created datetime default NOW() not null,
	modified datetime default NOW() null,
	constraint users_pk
		primary key (id),
	constraint users_uniq
		unique (user_id)
);

INSERT INTO recore.users (id, user_id, first_name, last_name, created, modified)
VALUES ('5edba4be-b7b8-451b-8c63-018cc0a88004', 1, 'Yvette', 'Marshall', '2020-06-06 14:14:22', '2020-06-06 14:14:22');
INSERT INTO recore.users (id, user_id, first_name, last_name, created, modified)
VALUES ('5edba61e-1d6c-4483-a777-01b0c0a88004', 2, 'Reece', 'Carter', '2020-06-06 14:20:14', '2020-06-06 14:20:14');
INSERT INTO recore.users (id, user_id, first_name, last_name, created, modified)
VALUES ('5edba620-8ea8-4791-8d5b-01bcc0a88004', 3, 'Jasmine', 'Robinson', '2020-06-06 14:20:16', '2020-06-06 14:20:16');
INSERT INTO recore.users (id, user_id, first_name, last_name, created, modified)
VALUES ('5edba621-eff8-4481-b980-01c8c0a88004', 4, 'Claire', 'Russell', '2020-06-06 14:20:17', '2020-06-06 14:20:17');
```

Old article splurge:

Further Reading:

* `server_id`:
  * https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_server_id
* `binlog_format`:
  * https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#sysvar_binlog_format
  * https://dev.mysql.com/doc/refman/8.0/en/binary-log-setting.html
* `binlog_expire_days`:
  * https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#sysvar_binlog_expire_logs_seconds
* `log-bin`:
  * https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#option_mysqld_log-bin

---

[17.1.2.3 Creating a User for Replication](https://dev.mysql.com/doc/refman/8.0/en/replication-howto-repuser.html)

Create a connection in Workbench or equivalent and run the following queries, or run the `docker exec` commands below.

| Server | Host | User | Pass | Host Port |
|--------|------|------|------|-----------|
| Master | `127.0.0.1` | `root` | `password` | `3366` |
| Slave  | `127.0.0.1` | `root` | `password` | `3367` |
 

![Workbench](https://thepracticaldev.s3.amazonaws.com/i/qfhz80urkiwkyu5yn97g.png)

We need to create a user account on the master that the slave can use to connect. It must have been granted the `REPLICATION SLAVE` privilege.

```
docker exec -i db_master bash -c "mysql --user=root --password=password" 2>/dev/null << "SQL"
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH caching_sha2_password BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
SQL
```

> The weird bash stuff here is `2>/dev/null` to throw away `stderr` i.e. `mysql: [Warning] Using a password on the command line interface can be insecure.`
> `<< "SQL"` (this is here-doc, the label is SQL and the label is quoted to [prevent backticks being evaluated](https://stackoverflow.com/a/13122217/5873008)) is redirecting these multiline queries to be executed.
> Later in the tutorial we'll use `<< SQL`, i.e. a here-doc with commands to be evaluated in it.

While we're focused on `master` we'll  `CREATE SCHEMA`, `CREATE TABLE` and `INSERT INTO` to have something to work with later.

```
docker exec -i db_master bash -c "mysql --user=root --password=password" 2>/dev/null << "SQL"
CREATE SCHEMA `core`;
CREATE TABLE `core`.`users` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `username` VARCHAR(45) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT NOW(),
  `updated_at` DATETIME NOT NULL DEFAULT NOW(),
  PRIMARY KEY (`id`)
);
INSERT INTO `core`.`users` (`username`) VALUES ('alistaircol');
SQL
```

That's enough configuration for the Master! Now to configure the slave.

## Slave (Read Replica)

Steps:

1. Set a distinct, non-zero `server-id` different from master.
2. Prepare a dump from `master` to get `slave` previous data (some data might not be in the binary logs to be replayed).
3. Import dump from previous step. 
4. Tell `slave` some things about `master` to get binary logs and `START SLAVE`

[17.1.2.2 Setting the Replication Slave Configuration](https://dev.mysql.com/doc/refman/8.0/en/replication-howto-slavebaseconfig.html)

The only thing we need to do is set the `server-id` of the slave in `./db/slave/my.cnf`:

```
[mysqld]
server_id = 2
```

---

[17.1.2.5 Creating a Data Snapshot using `mysqldump`](https://dev.mysql.com/doc/refman/8.0/en/replication-snapshot-method.html)

We need to an export/snapshot of `master` database to import into `slave` initially. I'll export data from `master` to my host machine running Docker.

```
docker exec -u $(id -u) db_master bash -c "mysqldump --master-data --user=root --password=password --databases core" > master.sql
``` 

The `--master-data` flag in the `mysqldump` command is very important. This saves you needing to manually obtain the master binary log coordinates later when we tell the `slave` instance to become a slave for master.

We're also adding `-u $(id -u)` in the `docker exec` command, this is so the output file has you (user running `docker exec` command) as the owner and you can read without `chown`ing or `sudo`.

---

[17.1.2.6 Setting Up Replication with Existing Data](https://dev.mysql.com/doc/refman/8.0/en/replication-setup-slaves.html#replication-howto-newservers)

Now we'll import the export given from `mysqldump` from previous step.

```
docker exec -i db_slave bash -c "mysql --user=root --password=password" < master.sql



Pretty:
pv master.sql | docker exec -i db_slave bash -c "mysql --user=root --password=password" 2>/dev/null
```

[17.1.2.7 Setting the Master Configuration on the Slave](https://dev.mysql.com/doc/refman/8.0/en/replication-howto-slaveinit.html)

Don't need to use log file and log pos here.

```
docker exec -i db_slave bash -c "mysql --user=root --password=password" 2>/dev/null << "SQL"
CHANGE MASTER TO MASTER_HOST = 'db_master';
START SLAVE USER = 'repl' PASSWORD = 'repl_password';
SQL
```

The above will lose binlog file and pos.

Try:

```
docker exec -i db_slave bash -c "mysql --user=root --password=password" << SQL
CHANGE MASTER TO 
  MASTER_HOST = 'db_master',
  MASTER_USER = 'repl',
  MASTER_PASSWORD = 'repl_password',
  MASTER_LOG_FILE = '$(docker exec -i db_master mysql --user=root --password=password --execute="SHOW MASTER STATUS\G;" 2> /dev/null | grep 'File: ' | awk '{print $2}')',
  MASTER_LOG_POS = $(docker exec -i db_master mysql --user=root --password=password --execute="SHOW MASTER STATUS\G;" 2> /dev/null | grep 'Position: ' | awk '{print $2}'),
  GET_MASTER_PUBLIC_KEY = 1;
START SLAVE;
SQL



```

See the slave's status:

```
docker exec -i db_slave mysql --user=root --password=password --execute="SHOW SLAVE STATUS\G;"
```


---

## Docker 'preamble'

`docker-composer.yml`:

```yaml
version: '3'
volumes:
  db-main-data:
    driver: local
  # yup, this sucks
  db-main-logs:
    driver: local
    driver_opts:
      type: tmpfs
      device: tmpfs
      o: size=100m,rw
  db-new-data:
    driver: local
  db-new-logs:
    driver: local

services:
  web:
    build:
      context: .
    image: ac_web
    container_name: ac_web
    env_file: '.web.env'
    volumes:
      - './:/var/www/html'
    ports:
      - '9090:80'
    depends_on:
      - db
      - db_new

  # Main repository of data is in here.
  # Code in web base uses this database.
  # Incremental upgrades will move functionality to db-new.
  # Some models still might have dependencies on db-new.
  # Will setup a data replication in here from db-new.
  db:
    image: mysql:8
    container_name: ac_db
    env_file: '.db.main.env'
    volumes:
      # trailing / is seriously important
      - 'db-main-data:/var/lib/mysql/'
      - 'db-main-logs:/var/log/mysql/'
      - '.db.main.cnf:/etc/mysql/my.cnf'
    ports:
      - '9393:3306'

  db_new:
    image: mariadb:10.4.12
    container_name: ac_new_db
    env_file: '.db.main.env'
    volumes:
      - 'db-new-data:/var/lib/mysql'
      - 'db-new-logs:/var/log/mysql'
      - '.db.new.cnf:/etc/mysql/my.cnf'
    ports:
      - '9394:3306'
```

A `php:apache` image base with a few utilities for quality of life.

`Dockerfile`:

```dockerfile
FROM php:7.4-apache
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
        apt-utils \
        pv \
        jq \
        zip \
        git \
        curl \
        nano \
        unzip \
        zlibc \
        zlib1g \
        libzip-dev \
    && docker-php-ext-install \
        zip \
        pdo \
        pdo_mysql \
    && a2enmod rewrite \
    && usermod -u 1000 www-data

COPY --from=composer:latest \
    /usr/bin/composer \
    /usr/bin/composer

WORKDIR /var/www/html

```

Start of a `Makefile`:

```makefile
.PHONY: install

install:
	docker-compose up \
		--build \
		--detach
	docker exec -it -u $(id -u) ac_web composer install

start:
	docker-compose up --remove-orphans

down:
	docker-compose down --remove-orphans
	docker volume rm --force mysql-cross-database-replication-cakephp_db-main-data
	docker volume rm --force mysql-cross-database-replication-cakephp_db-new-data
	docker volume rm --force mysql-cross-database-replication-cakephp_db-main-logs
	docker volume rm --force mysql-cross-database-replication-cakephp_db-new-logs

shell:
	docker exec -it -u $$(id -u) ac_web bash
	
```
