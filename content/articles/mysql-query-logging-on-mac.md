---
title: "MySQL query logging on Mac"
author: "Ally"
summary: "Enabling MySQL query logging on Mac (without Docker)"
publishDate: 2021-05-17T17:54:18+0100
tags: ['mysql']
draft: false
---

Run the following command to see which config files are loaded by MySQL/Mariadb:

```bash
mysql --verbose --help | grep my.cnf -B1
```

Output:

```text {hl_lines=[4,5]}
  -P, --port=#        Port number to use for connection or 0 for default to, in
                      order of preference, my.cnf, $MYSQL_TCP_PORT,
--
Default options are read from the following files in the given order:
/etc/my.cnf /etc/mysql/my.cnf /usr/local/etc/my.cnf ~/.my.cnf
```

I will append config to enable query logging later.

## Create Log File

First we need to create a file to log to.

```bash
sudo mkdir -p /var/log/mysql
sudo touch /var/log/mysql/mariadb.log
```

## Make Log File Writable
Make it writable for Mariabd - Pro-tip (probably is a bad idea) - get the user and group directly from the executable.

```bash
$ stat -f '%Su:%Sg' /usr/local/bin/mysql
alistaircollins:admin
````

```bash
sudo chown $(stat -f '%Su:%Sg' /usr/local/bin/mysql) /var/log/mysql/mariadb.log
```

<center>

![File Permissions](/img/articles/mysql-query-logging-mac/file-permissions.png)

</center>

```bash
sudo chmod 666 /var/log/mysql/mariadb.log
```

## Enable Query Logging in Config

Append config to enable query logging:

```bash
cat <<EOF >> /usr/local/etc/my.cnf
```

```ini
[mariadb]
general_log
general_log_file=/var/log/mysql/mariadb.log
```

```bash
EOF
```

## Restart Database Service

```bash
brew services restart mariadb
```

## View Logs

```bash
tail -fn10 /var/log/mysql/mariadb.log
# or
less +F /var/log/mysql/mariadb.log
```
