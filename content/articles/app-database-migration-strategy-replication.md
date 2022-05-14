---
title: "Possible Incremental Code & Database Migration Strategy"
author: "Ally"
summary: "MySQL database replication where a new application becomes single source of truth but a legacy application still needs access to database. Or simply a strategy to allow 'cross-database' joins."
publishDate: 2020-06-11T12:00:00+01:00
tags: ['mysql']
draft: true
---

**TL;DR**:

* Incremental migration of features from legacy system to new platform.
* New platform will be the single source of truth, however legacy application still needs direct database access (read-only) to function while the long migration is in progress.
* Legacy system has lots of data dependencies, so it's hard to identify them all and fix accordingly. Cross-database joins aren't really a thing.
* Set up database replication so legacy system has access to new platform data within same legacy system database.
* Clone the repo [here](https://github.com/alistaircol/cakephp-mysql-replication-migration-strategy)

---

# TODO

* Add 3rd data source - this will be `recore` in `core` instance.
* Keep 2nd datasource `recore` instance just for some demonstration purposes.

---

We are developing a new (Symfony) codebase (codename: `recore`), incrementally migrating features from the old (CakePHP 2.x) codebase (codename: `core`).
We will migrate smaller features to `recore`, but `core` will still have dependencies which aren't going to be migrated since it's incremental instead of a big switchover.

* `recore`: MariaDB 10
* `core`: MySQL 8

Some docker setup preamble is at the end of the article since it isn't the entire focus of this article.

This is covering local development as a proof of concept. For stage/production instructions, too bad! Maybe later.

---

## Local development in Docker

You can skip this if you don't care about it. It's nothing earth-shattering, just some volumes and config.

A `php:apache` image base with a few utilities for quality of life.

`Dockerfile`:

```dockerfile {linenos=true}
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

`docker-compose.yml`:

```yaml {linenos=true}
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
    image: web
    container_name: web
    env_file: '.web.env'
    volumes:
      - './:/var/www/html'
    depends_on:
      - core
      - recore

  core:
    image: mysql:8
    container_name: db_core
    env_file: 'core.env'
    volumes:
      # trailing / is seriously important
      - 'db-main-data:/var/lib/mysql/'
      - 'db-main-logs:/var/log/mysql/'
      - './core.cnf:/etc/mysql/my.cnf'

  recore:
    image: mariadb:10.4.12
    container_name: db_recore
    env_file: 'recore.env'
    volumes:
      - 'db-new-data:/var/lib/mysql'
      - 'db-new-logs:/var/log/mysql'
      - './recore.cnf:/etc/mysql/my.cnf'
```

## Initial MySQL configuration & data

The `recore` database needs some special config to use binary logging for replication.

`recore.cnf`:

```text
[mysqld]
server_id = 1
binlog_format = ROW
expire_logs_days = 7
log_bin = /var/lib/mysql/bin-log
binlog_do_db = recore
```

More info on each of these options:

* [`server_id`](https://dev.mysql.com/doc/refman/8.0/en/replication-options.html#sysvar_server_id)
* [`binlog_format`](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#sysvar_binlog_format) ` = ` [`ROW|STATEMENT|MIXED`](https://dev.mysql.com/doc/refman/8.0/en/binary-log-formats.html)
* [`expire_logs_days`](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#sysvar_expire_logs_days)
* [`log_bin`](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#option_mysqld_log-bin)
* [`binlog_do_db`](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html#option_mysqld_binlog-do-db)
* [MariaDB: Configuring the Master](https://mariadb.com/kb/en/setting-up-replication/#configuring-the-master)

The first logical feature to move over is users & auth. We will migrate this to `recore`.

First we'll create a user `repl:repl_password` on this instance. Later on the `core` instance can connect and replicate
`recore` onto its instance. `core` instance can then have access to the data it once had and can query with no problems.

`recore.sql`:

```mysql
drop user if exists repl;
create user if not exists 'repl'@'%' 
identified by 'repl_password';

grant replication slave on *.* to 'repl'@'%';
flush privileges;

drop schema if exists `recore`;
create schema if not exists `recore`;

create table recore.users
(
	id char(36) not null,
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

If you're following along to import, it is:

```bash
pv core.sql | docker exec \
    --interactive \
    db_core \
    mysql \
    --user=root \
    --password=password
```

---

Have yet to migrate over the `notes` feature, so it's still in `core` instance.

`core.sql`:

```mysql
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
INSERT INTO core.notes (id, note_id, content, user_id, created, updated, pinned)
VALUES ('5edba6c2-c3a4-4d63-abb0-02dcc0a88004', 10, 'quas et quae suscipit mollitia id quasi ea vero quia et quibusdam tenetur autem ea inventore aliquid quis quia', '5edba61e-1d6c-4483-a777-01b0c0a88004', '2020-06-06 14:22:58', '2020-06-06 14:22:58', null);
```

You can see that the `notes` has a dependency `user_id`, i.e. author.

If you're following along to import, it is:

```bash
pv recore.sql | docker exec \
    --interactive \
    db_recore \
    mysql \
    --user=root \
    --password=password
```

## Configuring `core` datasources and seeing the problem

Configuring our datasources for the `core` project. The database credentials for both sources are in
`.web.env` and are set as environment variables in the `web` container.

`app/Config/database.php`:

```php
<?php
class DATABASE_CONFIG
{
    public array $default; // i.e. core
    public array $recore;

    public function __construct()
    {
        $this->default = [
            'datasource' => 'Database/Mysql',
            'persistent' => false,
            'host'       => getenv('CORE_HOST'),
            'login'      => getenv('CORE_USER'),
            'password'   => getenv('CORE_PASS'),
            'database'   => 'core',
            'prefix'     => '',
        ];
        $this->recore = [
            'datasource' => 'Database/Mysql',
            'persistent' => false,
            'host'       => getenv('RECORE_HOST'),
            'login'      => getenv('RECORE_USER'),
            'password'   => getenv('RECORE_PASS'),
            'database'   => 'recore',
            'prefix'     => '',
        ];
    }
}
```

This will work when using `contain` in the ORM query, since that does a subquery.

Example:

```php
<?php
$data = $this->Note->find('all', [
    'contain' => [
        'User',
    ]
]);
```

```text
^ array:10 [
  0 => array:2 [
    "Note" => array:7 [
      "id" => "5edba6ad-566c-46a9-ab0e-0270c0a88004"
      "note_id" => "1"
      "content" => "molestiae dolores nemo aliquam velit unde error perferendis minus officia ut tenetur vitae veniam eveniet eveniet quas"
      "user_id" => "5edba620-8ea8-4791-8d5b-01bcc0a88004"
      "created" => "2020-06-06 14:22:37"
      "updated" => "2020-06-06 14:22:37"
      "pinned" => null
    ]
    "User" => array:6 [
      "id" => "5edba620-8ea8-4791-8d5b-01bcc0a88004"
      "user_id" => "3"
      "first_name" => "Jasmine"
      "last_name" => "Robinson"
      "created" => "2020-06-06 14:20:16"
      "modified" => "2020-06-06 14:20:16"
    ]
  ]
 [truncated]
```

The query logs (prettified a little):

`core`:

```text {linenos=table}
2020-06-11T13:38:41.399530Z 11 Connect  root@web.mysql-cross-database-replication-cakephp_default on core using TCP/IP
2020-06-11T13:38:41.399926Z 11 Query    SHOW TABLES FROM `core`
2020-06-11T13:38:41.401522Z 11 Query    SHOW FULL COLUMNS FROM `core`.`notes`
2020-06-11T13:38:41.402915Z 11 Query    SELECT CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLLATIONS WHERE COLLATION_NAME = 'utf8mb4_0900_ai_ci'
2020-06-11T13:38:41.405017Z 11 Query    SELECT `Note`.`id`, 
                                            `Note`.`note_id`,
                                            `Note`.`content`,
                                            `Note`.`user_id`, 
                                            `Note`.`created`, 
                                            `Note`.`updated`,
                                            `Note`.`pinned` 
                                        FROM `core`.`notes` AS `Note`
                                        WHERE 1 = 1
2020-06-11T13:38:41.418441Z 11 Quit 
```

`recore`:

```text {linenos=table}
200611 13:38:41     22 Connect  root@web.mysql-cross-database-replication-cakephp_default as anonymous on recore
                    22 Query    SHOW TABLES FROM `recore`
                    22 Query    SHOW FULL COLUMNS FROM `recore`.`users`
                    22 Query    SELECT CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLLATIONS WHERE COLLATION_NAME = 'latin1_swedish_ci'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba620-8ea8-4791-8d5b-01bcc0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba621-eff8-4481-b980-01c8c0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba61e-1d6c-4483-a777-01b0c0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba620-8ea8-4791-8d5b-01bcc0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba4be-b7b8-451b-8c63-018cc0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba620-8ea8-4791-8d5b-01bcc0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba621-eff8-4481-b980-01c8c0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba620-8ea8-4791-8d5b-01bcc0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba61e-1d6c-4483-a777-01b0c0a88004'
                    22 Query    SELECT `User`.`id`, `User`.`user_id`, `User`.`first_name`, `User`.`last_name`, `User`.`created`, `User`.`modified` FROM `recore`.`users` AS `User`   WHERE `User`.`id` = '5edba4be-b7b8-451b-8c63-018cc0a88004'
                    22 Quit 
```

*tangent*: Man, I hate this default timestamp. `show variables where variable_name = 'log_timestamps'` in `core` = `'UTC'`. Can't see a way to configure this for MariaDB.

![wtf](/img/memes/angry-at-keyboard.jpg)

While you can do 'cross database/schema' joins within the same instance, you can't really do it if they're on separate instances.

Think of this example: `database_name`.`table_name`

```php
<?php
$data = $this->Note->find('all', [
   'joins' => [
       [
           'table' => $this->User
                ->getDataSource()
                ->config['database'] . '.users',
           'alias' => 'User',
           'type'  => 'INNER',
           'conditions' => [
               'User.id = Note.user_id',
           ]
       ]
   ]
]);
````

Since `Note` is in `core` and `User` in `recore` there is predictably an error:

```text
Error: SQLSTATE[42000]: Syntax error or access violation: 1049 Unknown database 'recore'
```

`core`:

```text
2020-06-11T14:31:15.784494Z 9 Connect   root@web.mysql-cross-database-replication-cakephp_default on core using TCP/IP
2020-06-11T14:31:15.785029Z 9 Query     SHOW TABLES FROM `core`
2020-06-11T14:31:15.789334Z 9 Query     SHOW FULL COLUMNS FROM `core`.`notes`
2020-06-11T14:31:15.791056Z 9 Query     SELECT CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLLATIONS WHERE COLLATION_NAME = 'utf8mb4_0900_ai_ci'
2020-06-11T14:31:15.793105Z 9 Query     SELECT 
                                            `Note`.`id`,
                                            `Note`.`note_id`,
                                            `Note`.`content`,
                                            `Note`.`user_id`,
                                            `Note`.`created`,
                                            `Note`.`updated`,
                                            `Note`.`pinned`
                                        FROM `core`.`notes` AS `Note`
                                        INNER JOIN `recore`.`users` AS `User` ON (`User`.`id` = `Note`.`user_id`)
                                        WHERE 1 = 1
2020-06-11T14:31:15.793809Z 9 Quit 
```

Yes, this is a trivial example and migrating `Note` over would be a relatively straightforward thing, but there's much
more just like this, and they aren't as trivial, hence a replication strategy might be the option.

---

## Setting up Slave in `core` to replicate `recore` data

It's all been pretty simple so far, here is where things get interesting.

Steps for `core`:

1. Set a distinct, non-zero [`server_id`](https://dev.mysql.com/doc/refman/8.0/en/replication-options.html#sysvar_server_id) different from master, i.e. `recore`.
2. Prepare a dump from master, i.e. `recore` for import slave, i.e. `core`. This is because some data might not be in the binary logs to be replayed.
3. Import dump from master, i.e. `recore` from previous step into `core`. 
4. Tell slave, i.e. `core` some things about master, i.e. `recore` to get binary logs and `START SLAVE`.

[`17.1.2.2` Setting the Replication Slave Configuration](https://dev.mysql.com/doc/refman/8.0/en/replication-howto-slavebaseconfig.html)

The only thing we need to do is set the [`server_id`]((https://dev.mysql.com/doc/refman/8.0/en/replication-options.html#sysvar_server_id)) of the slave in `recore.cnf`:

```text
[mysqld]
server_id = 1
```

---

[`17.1.2.5` Creating a Data Snapshot using `mysqldump`](https://dev.mysql.com/doc/refman/8.0/en/replication-snapshot-method.html)

We need to an export/snapshot of master, i.e `recore` database to import into slave, i.e. `core` initially.

```bash
cat <<"SH" | docker exec -i db_recore bash > master.sql
mysqldump \
    --master-data \
    --user=root \
    --password=password \
    --databases recore
SH
``` 

The [`--master-data`](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html#option_mysqldump_master-data) flag in the `mysqldump` command is very important. This saves you needing to manually obtain the master binary log coordinates later.

---

[`17.1.2.6` Setting Up Replication with Existing Data](https://dev.mysql.com/doc/refman/8.0/en/replication-setup-slaves.html#replication-howto-newservers)

Now we'll import the export given from `mysqldump` from previous step.

```bash
pv master.sql | docker exec \
    --interactive \
    db_core \
    mysql \
    --user=root \
    --password=password \
    2>/dev/null
```

[`17.1.2.7` Setting the Master Configuration on the Slave](https://dev.mysql.com/doc/refman/8.0/en/replication-howto-slaveinit.html)

Let slave, i.e. `core` know about master, i.e. `recore` to start replaying binary logs.

```bash
cat <<SQL | docker exec -i \
    db_core \
    mysql \
    --user=root \
    --password=password
CHANGE MASTER TO
    MASTER_HOST = 'db_recore',
    MASTER_USER = 'repl',
    MASTER_PASSWORD = 'repl_password',
    MASTER_LOG_FILE = '$(
        docker exec --interactive \
            db_recore \
            mysql \
            --user=root \
            --password=password \
            --execute="SHOW MASTER STATUS\G;" \
            2>/dev/null \
            | grep 'File: ' \
            | awk '{print $2}'
    )',
    MASTER_LOG_POS = $(
        docker exec --interactive \
            db_recore \
            mysql \
            --user=root \
            --password=password \
            --execute="SHOW MASTER STATUS\G;" \
            2>/dev/null \
            | grep 'Position: ' \
            | awk '{print $2}'
    );
START SLAVE;
SQL
```

Checking the slave, i.e. `core` status:

```bash
cat <<"SQL" | docker exec -i \
    db_core \
    mysql \
    --user=root \
    --password=password
SHOW SLAVE STATUS\G;
SQL
```

And it (hopefully) works!

```text
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: db_recore
                  Master_User: repl
                  Master_Port: 3306
                Connect_Retry: 60
              Master_Log_File: bin-log.000003
          Read_Master_Log_Pos: 3332
               Relay_Log_File: 29bd4b18a9fa-relay-bin.000002
                Relay_Log_Pos: 453
        Relay_Master_Log_File: bin-log.000003
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB: 
          Replicate_Ignore_DB: 
           Replicate_Do_Table: 
       Replicate_Ignore_Table: 
      Replicate_Wild_Do_Table: 
  Replicate_Wild_Ignore_Table: 
                   Last_Errno: 0
                   Last_Error: 
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 3332
              Relay_Log_Space: 669
              Until_Condition: None
               Until_Log_File: 
                Until_Log_Pos: 0
           Master_SSL_Allowed: No
           Master_SSL_CA_File: 
           Master_SSL_CA_Path: 
              Master_SSL_Cert: 
            Master_SSL_Cipher: 
               Master_SSL_Key: 
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error: 
               Last_SQL_Errno: 0
               Last_SQL_Error: 
  Replicate_Ignore_Server_Ids: 
             Master_Server_Id: 1
                  Master_UUID: 
             Master_Info_File: mysql.slave_master_info
                    SQL_Delay: 0
          SQL_Remaining_Delay: NULL
      Slave_SQL_Running_State: Slave has read all relay log; waiting for more updates
           Master_Retry_Count: 86400
                  Master_Bind: 
      Last_IO_Error_Timestamp: 
     Last_SQL_Error_Timestamp: 
               Master_SSL_Crl: 
           Master_SSL_Crlpath: 
           Retrieved_Gtid_Set: 
            Executed_Gtid_Set: 
                Auto_Position: 0
         Replicate_Rewrite_DB: 
                 Channel_Name: 
           Master_TLS_Version: 
       Master_public_key_path: 
        Get_master_public_key: 0
            Network_Namespace: 
```

---

## Unresolved Problems

* Unit testing. - CakePHP 2.x only allows one `test` database. This gets complicated, might then need
to use prefixes, and some exotic import scripts and `Fixture`s. 
* Possibly preventing writes to `recore` from `core` codebase.

```php
<?php
App::uses('Model', 'Model');

class ReadOnlyModel extends Model
{
    public function __construct($id = false, $table = null, $ds = null)
    {
        parent::__construct($id, $table, $ds);
    }

    public function setAssociatedDatasourcesIfTesting()
    {
        $this->setDataSource('coreRecoreReplica');
    }
}
```

## Local sync from production database(s)

Probably will follow a similar process to the above.

However, unsure if we will export with `--master-data` and how that `CHANGE MASTER` will look, but I imagine it will be the same.

## Staging sync from production database(s)

Come back later, might have filled this gap!
