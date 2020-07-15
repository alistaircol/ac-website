---
title: "PHP with RabbitMQ"
author: "Ally"
summary: "TODO"
publishDate: 2020-06-07T00:00:00+01:00
tags: ['docker', 'php', 'rabbitmq']
draft: true
toc: true
---

Might be good to start here: https://symfonycasts.com/screencast/messenger/amqp

* https://www.cloudamqp.com/

A good place to start is [RabbitMQ in 5 Minutes](https://www.youtube.com/watch?v=deG25y_r6OY).

```bash
docker run \
    --rm
    --hostname ac-rabbitmq \
    --name ac-rabbitmq \
    -p 127.0.0.1:15672:15672 \
    rabbitmq:3-management
```

It's given a `name` to poke around inside, e.g. `docker exec -it ac-rabbitmq bash`.

We will want to configure the instance, add exchanges, queues, route bindings, etc. Go to [`http://localhost:15672/`](http://localhost:15672/)
and login with `guest:guest`.

If that's not for you, more information can be found in the API by going to [`http://localhost:15672/api/index.html`](http://localhost:15672/api/index.html).

When you are done, you can export the instance configuration:

```bash
curl --user guest:password \
    http://localhost:15672/api/definitions \
    | jq . > definitions.json
```

Now, to persist these changes and share with your friends you'll want to load these definitions.

`/etc/rabbitmq/rabbitmq.conf`:

```diff
+management.load_definitions = /etc/rabbitmq/definitions.json
```

Your `docker run` command will now look something like this to load the definitions:

```diff
 docker run \
     --rm
     --hostname ac-rabbitmq \
     --name ac-rabbitmq \
     -p 127.0.0.1:15672:15672 \
+    -v "$(pwd)/definitions.js:/etc/rabbitmq/definitions.json"
     rabbitmq:3-management
```

---

## [`phpamqp`](https://github.com/php-amqplib/php-amqplib)

```bash
composer require php-amqplib/php-amqplib
```

A CakePHP 2.x example:

```php
<?php

use PhpAmqpLib\Connection\AMQPStreamConnection;
use PhpAmqpLib\Message\AMQPMessage;

class RabbitQueueShell extends AppShell
{
    private $connection;
    private $channel;

    public function __construct()
    {
        $this->connection = new AMQPStreamConnection('ac-rabbitmq', 5672, 'guest', 'guest');
        $this->channel = $this->connection->channel();
        $this->channel->queue_declare('ac_default', false, true, false, false);

        parent::__construct();
    }

    public function main()
    {
        $this->out('A console command to test consumption of rabbitmq messages');
    }

    // ./Vendor/bin/cake RabbitQueue send blah blah
    public function send()
    {
        $data = explode(' ', $this->args[0]);
        $msg = new AMQPMessage(
            $data[1] ?? 'i will be consumed right away!',
            [
                'delivery_mode' => AMQPMessage::DELIVERY_MODE_PERSISTENT
            ]
        );
        $this->channel->basic_publish($msg, '', 'ac_default');
        $this->out(" [x] Sent ".$data[1]);
        $this->down();
    }

    // ./Vendor/bin/cake RabbitQueue worker
    public function worker()
    {
        $this->out(" [*] Waiting for messages. To exit press CTRL+C");
        $this->channel->basic_consume('ac_default', '', false, false, false, false, function ($msg) {
            $this->out(' [x] Received ' . $msg->body);
            // do whatever
            // TODO: dump $msg and show here
            $this->out('[x] Done');

            // send ack
            $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        });

        while ($this->channel->is_consuming()) {
            $this->channel->wait();
        }
        $this->down();
    }

    private function down()
    {
        $this->out('closing worker');
        $this->channel->close();
        $this->connection->close();
    }
}

```

TODO:

* screenshots
* maybe some CI and learn how to publish to registry
