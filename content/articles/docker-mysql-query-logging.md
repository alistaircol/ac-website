---
title: "Getting MySQL's Docker container* query logging to go to stdout and take advantage of Docker's logging"
author: "Ally"
summary: "A tedious adventure for what others see as a pointless exercise. Basically, this will walk you through an approach to throw `general_log` to `stdout` and then you can configure the logging engine for your needs. This wasn't enough pain for me, so I set up `bash` script to `tail` MySQL's `general_log` to construct custom GELF messages to add extra context (such as the correct source container) into a local `graylog` stack, or any other `GELF` thingie."
publishDate: 2020-07-19T00:00:00+01:00
tags: ['docker', 'mysql', 'bash', 'graylog']
draft: false
---

Having MySQL's `general_log` enabled is excellent for debugging queries made by an application or ORM.
Some frameworks might not have the ability to log this raw query, etc. so this is solution that should apply to all applications.

Currently, I have it configured to log inside the container at `/var/log/mysql/mysql.log`.

`docker-compose.yml`:

```yaml
volumes:
    - "./my.cnf:/etc/mysql/my.cnf"
```

`/etc/mysql/mysql.cnf`:

```text
[mysqld]
general_log = 1
general_log_file = /var/log/mysql/mysql.log
```

This works fine, **but** it can sometimes be a bit of a pain. In my work environment with `tmux` I'd need to jump to the correct pane and enter scroll mode to have a look for the query. First world problems, I know.

---

Having it in a proper log search tool, like `graylog` or some other ELK thing, is the next step.

Unfortunately, there are so many issues having `general_log`, etc. to go directly to `stdout`, and I ultimately found it not to be possible to just have it log to either `stdout` or `stderr` like Docker recommends, for the logs to show in the `docker logs` or `docker-compose logs` commands.

This is the command I've been using for a long time in one of my `tmux` panes, which works fine.

```shell script
docker exec -it ac_db bash -c "tail -fn10 /var/log/mysql/mysql.log"
```

### Setting up graylog

If you have a graylog instance already then you can skip this part.

The `docker-compose.yml` is virtually the same as given in the graylog [docs](https://docs.graylog.org/en/3.3/pages/installation/docker.html). 

```yaml
version: "3"
services:
    mongo:
        image: mongo:3
        volumes:
            - mongo_data:/data/db
        networks:
            - graylog

    # Elasticsearch: https://www.elastic.co/guide/en/elasticsearch/reference/6.x/docker.html
    elasticsearch:
        image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.8.5
        volumes:
            - es_data:/usr/share/elasticsearch/data
        environment:
            - http.host=0.0.0.0
            - transport.host=localhost
            - network.host=0.0.0.0
            - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
        networks:
            - graylog

    # Graylog: https://hub.docker.com/r/graylog/graylog/
    graylog:
        image: graylog/graylog:3.3
        container_name: qa_graylog
        volumes:
            - graylog_journal:/usr/share/graylog/data/journal
        environment:
            # CHANGE ME (must be at least 16 characters)!
            - GRAYLOG_PASSWORD_SECRET=fNHRWw7tUUUE5Mnv
            # Password: fNHRWw7tUUUE5Mnv
            - GRAYLOG_ROOT_PASSWORD_SHA2=432fc5c862c24d97b38fb8cca142de0b57693a76a08051d8fc702d909520786e
            - GRAYLOG_HTTP_EXTERNAL_URI=http://127.0.0.1:9000/
        networks:
            - graylog
        depends_on:
            - mongo
            - elasticsearch
        ports:
            # Graylog web interface and REST API
            - 9000:9000
            # GELF UDP
            - 12201:12201/udp

# Volumes for persisting data, see https://docs.docker.com/engine/admin/volumes/volumes/
volumes:
    mongo_data:
        driver: local
    es_data:
        driver: local
    graylog_journal:
        driver: local

networks:
    graylog:
        driver: bridge
```

First thing to do:

* Log in to graylog, default URL is [`127.0.0.1:9000`](http://127.0.0.1:9000)
    * Username: `admin`
    * Password: `fNHRWw7tUUUE5Mnv`
* Create new input.
    * Go to `Inputs`, this is from the `System / Inputs` menu
    * Select `GELF UDP` from the `Select input` dropdown menu
    * Click `Launch new input`
    * Select your node (I went for `global`, the node `id` kept changing for me when `docker` restarts, therefore next time it would start, the input was not started and listening for messages)
    * Give a title
    * Click save
    * Start the input if not already started
    
The graylog instance should now be able to receive logs.

---

Testing with `nc`?:

Later, I am going to use [GELF](https://docs.graylog.org/en/3.3/pages/gelf.html#gelf-payload-specification) (Graylog Extended Log Format) messages to feed all logs into my local graylog stack. This is a natively logging engine supported by `docker` so any other containers, such as our `apache`/`php` containers will go into this effortlessly.


### Feeding `graylog` Some Logs

This will be simple, for any proper containers with logging set up to be fed into graylog, it's relatively simple to configure.

Slightly truncated `docker-compose.yml`:

```yaml
services:
    ac_crm:
        logging:
            driver: gelf
            options:
                gelf-address: "udp://127.0.0.1:12201"
                tag: "ac_crm"
```

The `gelf-address` is relative to the host machine running `docker`, and does not refer to the actual container.

This can be configured globally, and more options - more information on [configuring logging drivers](https://docs.docker.com/config/containers/logging/configure/).

### MySQL Logs

As mentioned above, I tried many things and other people smarter than me seem to be unable to get `general_log`, etc. to go to `stdout`/`stderr` without losing the benefit of using an official image.

Tried adding `mysql` user to `tty` group as suggested [here](https://stackoverflow.com/a/54134699/5873008). I tried to `chmod` `/dev/stdout` and `/dev/stderr` suggested [here](https://github.com/moby/moby/issues/31243#issuecomment-406879017) and many other solutions until I exhausted a few pages of Google search results.

---

Ultimately I decided to roll my own `bash` script and thrown it into its own container.

The container is quite simple. It contains `docker` so it can run the `bash` script - which will run `docker exec` commands to tail database log files and create a GELF message, and send it.

There are many cons about running `docker` within a container that I won't get into.

---

Adding the container to your app stack. Just for convenience.

Since we can't use a volume to use `logger.sh` and `CMD ["bash" "/app/logger.sh"]` since it won't be found, the following command is handy to rebuild the container.

```shell script
docker build --file=logging/Dockerfile --tag=ac_db_logging logging/
```

`docker-compose.yml`:  

```yaml
services:
    ac_db:
        image: mysql:5.7
        container_name: ac_db

    db_logging:
        build:
            context: ./logging
        image: ac_db_logging:latest
        container_name: ac_db_logging
        user: root
        depends_on:
            - ac_db
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock"
```

* **TODO**: show `db_logging` output with it to `stdout`.
* **TODO**: show `db_logging` output with `gelf` in `graylog`.


---

Just copy `docker`, the `logger.sh` script and make it executable.

`logging/Dockerfile`:

```dockerfile
FROM ubuntu:20.04
COPY --from=docker:latest /usr/local/bin/docker /usr/local/bin/docker
COPY logger.sh /app/logger.sh
RUN chmod +x /app/logger.sh
USER root
CMD ["./app/logger.sh"]
```

---

This is where the magic happens.

Takes each line from `general_log` and parse to construct a GELF message and send.

Unfortunately, if there are multiple lines in your query, this isn't logged correctly.

Disappointing but will try to fix this.

Some typical output from `general_log` to give some context to some of the commands in the script:

```text
2020-07-19T21:15:21.502856Z	    2 Connect	root@ac_crm.ac on ac_crm using TCP/IP
2020-07-19T21:15:21.503015Z	    2 Query	SET NAMES utf8
2020-07-19T21:15:21.504037Z	    2 Query	SHOW TABLES FROM `ac_crm`
2020-07-19T21:15:21.505134Z	    2 Query	SHOW FULL COLUMNS FROM `ac_crm`.`users`
2020-07-19T21:15:21.510187Z	    2 Query	SELECT CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLLATIONS WHERE COLLATION_NAME = 'utf8_general_ci'
2020-07-19T21:15:21.516580Z	    2 Quit
```

`logging/logger.sh`:

```shell script
#!/usr/bin/env bash
function send_to_graylog
{
    input=$(</dev/stdin)

    # convert mysql log timestamp to unix time
    # 2020-07-19T13:16:54.658820Z
    original_timestamp=$(echo "$input" | cut -c1-27)
    timestamp=$(date -d "$original_timestamp" +%s)

    # query transaction number
    # get the first number after timestamp
    transaction=$(echo "$input" | awk '{print $2}')

    # query command
    # third word
    command=$(echo "$input" | awk '{print $3}')

    # query
    # remove the first 3 words, i.e. timestamp, transaction number and command
    # and then remove leading spaces
    # https://www.cyberciti.biz/faq/unix-linux-bsd-appleosx-skip-fields-command/
    message=$(echo "$input" | awk '{$1="";$2="";$3=""; print}' | sed -e 's/^[[:space:]]*//')

    # https://docs.graylog.org/en/3.3/pages/gelf.html#gelf-payload-specification
    # maybe replace this with jq
    read -r -d '' output <<EOF
{
    "version": "1.1",
    "host": "ac_db",
    "short_message": "$message",
    "timestamp": "$timestamp",
    "_transaction": $transaction,
    "_command": "$command"
}
EOF

    echo "$output" | nc -u -w1 127.0.0.1 12201
}
# mariadb annoyingly chooses less superior date format for this.
mysql_ts_regex=^[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z
graylog_line=''
while read -r line ; do
    # if the line is a timestamp and the graylog_line is > 1
    # then send the current message and reset it
    if [[ $line =~ $mysql_ts_regex && ! -z "$graylog_line" ]]; then
        # TODO: need to convert to GELF before sending on
        echo "$graylog_line" | send_to_graylog
        graylog_line=''
    fi

    # if line starts with timestamp, then start graylog_line
    # else, i.e. it's a continuation, concat
    if [[ $line =~ $mysql_ts_regex ]]; then
        graylog_line=$line
    else
        graylog_line=$(echo -e "$graylog_line\n$line")
    fi
done < <(docker exec -t ac_db bash -c "tail -Fqn0 /var/log/mysql/mysql.log")
```

The above works as intended, but messages were trickling into server pretty slowly.

TODO: figure out this slowness.

### Debugging

Start a `nc` server to clearly see the data that would be sent. Running the script with `-x` is handy but quite difficult to see what is going on.


```shell script
nc -klvu 127.0.0.1 5000
```

Test that you can see what it is being sent:

```shell script
cat <<"EOF" | nc -u -w1 127.0.01 5000
This is a long message
EOF
```

Test message:

```shell script
cat <<"EOF" | nc -u -w1 127.0.01 12201
{
    "version": "1.1",
    "host": "test",
    "short_message": "this is a manual GELF message from cli"
}
EOF
```
