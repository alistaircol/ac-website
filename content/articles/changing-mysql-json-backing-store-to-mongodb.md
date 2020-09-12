---
title: "Changing semi-unstructured JSON data in a MySQL backing store to MongoDB"
author: "Ally"
summary: "Moving our semi-unstructured data from a `mysql` database, stored in a `json` column to a `mongodb` instance for better performance."
publishDate: 2020-09-11T00:00:00+01:00
draft: true
tags: ['mongodb', 'mysql', 'csv', 'solr']
---

**Rationale** Querying our semi-unstructured data which is currently in JSON column in a MySQL database gives quite poor performance, so looking to use something else. I tried Solr earlier, but MongoDB has been much easier to get up and running.

We will export the JSON data to CSV and import the csv data to MongoDB. Also, will need to start work on replacing the current implementation of CRUD to go to our new backing store.

This is what I've figured out so far, and it looks like a promising option to switch to! 

### Exporting JSON column to a CSV file

Exporting the JSON to CSV might look something like this. The first row of the CSV should be **all** possible JSON keys.

```php
<?php

class ExportUnstructuredDataCommand
{
  public function exportDataToCsv()
  {
    // mounted to guest PC by docker volume
    $output_path = '/var/www/html/data.csv';

    $csv = \League\Csv\Writer::createFromPath($output_path, 'w+');

    // ORM for MySQL database
    $records = $this->SemiUnstructuredData->find('all', [
      'fields' => [
        // name of the JSON column is unimaginatively called data
        'SemiUnstructuredData.data',
      ]
    ]);

    $header_set = 0;
    foreach ($records as $alpha_policy) {
      $record = json_decode($alpha_policy['SemiUnstructuredData']['data'], true);
      // this amazing dataset has a blank key and value...
      // causes issues when doing update/replace in mongodb later on
      if (array_key_exists('', $record)) {
        unset($record['']);
      }

      if (!$header_set) {
        $csv->insertOne(array_keys($record));
        $csv->insertOne($record);
        $header_set = true;
        continue;
      }
      $csv->insertOne($record);
    }

    this->out('Done');
  }
}
```

## Docker Setup

A slightly truncated `docker-compose.yml`.

* `mongodb` is the main thing.
* `mongo-express` is just a frontend to see what's going on - it is not recommended to use this in production!

```yaml
version: '3'
services:
    # ommited php containers and other stuff

    mongodb:
        image: mongo
        container_name: ac_mongodb
        environment:
            MONGO_INITDB_ROOT_USERNAME: root
            MONGO_INITDB_ROOT_PASSWORD: example
            MONGO_INITDB_DATABASE: alistaircol
        volumes:
            - "mongodb_data:/data/db"

    mongo-express:
        image: mongo-express
        container_name: ac_mongodb_express
        environment:
            # services.mongodb.container_name
            ME_CONFIG_MONGODB_SERVER: ac_mongodb
            ME_CONFIG_MONGODB_ADMINUSERNAME: root
            ME_CONFIG_MONGODB_ADMINPASSWORD: example
        ports:
            - "8081:8081"
        depends_on:
            - mongodb

volumes:
    mongodb_data:
```

### `mongodb`
 
**Importing** the `csv` data with [`mongoimport`](https://docs.mongodb.com/v4.2/reference/program/mongoimport/) is mostly self-explanatory.

Remember to `docker cp` file into `ac_mongo` container. The default `pwd` for `mongo` is `/`.

```bash
mongoimport \
    --type=csv \
    --db=alistaircol \
    --collection=policy_data \
    --headerline \
    --drop \
    --authenticationDatabase admin \
    --username=root \
    --password=example \
    data.csv
```

**Exporting** the collection will be important too. Will need this for local development/staging environment sync as well as for backup restoration if something bad happens.

Binary export of `policy_data` collection in `alistaircol` database.

```bash
docker exec ac_mongodb bash -c 'mongodump \
    --db=alistaircol \
    --collection=policy_data \
    --archive \
    --authenticationDatabase admin \
    --username=root \
    --password=example' \
    > policy_data.archive
```

Binary import of `policy_data.archive`:

```bash
docker exec qa_mongodb bash -c 'mongorestore \
    --authenticationDatabase admin \
    --username=root \
    --password=example \
    --db=alistaircol \
    --collection=policy_data \
    - ' \
    < policy_data.archive
```

### `mongodb-express`

Just after starting the container after login:

![mongo-express](/img/articles/mongodb-php/mongo-express.png)

### `php`

I use a bespoke `docker` image, but it's ultimately based on `php:7.3-apache`.

For it to be able to communicate with `mongodb`, I had to do the following:

* Install these new packages [why?](https://github.com/doctrine/DoctrineMongoDBBundle/issues/450#issuecomment-398108400):

```dockerfile
RUN apt-get install -y libcurl4-openssl-dev \
    pkg-config \
    libssl-dev
```  

* Install and enable the `mongodb` php extension:

```dockerfile
RUN pecl install mongodb-1.8.0
RUN docker-php-ext-enable mongodb
```

It might be possible to just do:

```dockerfile
RUN docker-php-ext-install mongodb
```

This seems to be all I needed to do for `pdo`, `pdo_mysql`, `sockets`.

---

![app](/img/articles/mongodb-php/php-app-grid.png)

### Connection (or an interface to the Collection)

I just need to do simple reads and updates for now on a single collection, so `$collection` is going to be the starting point for all other samples.

```php
<?php
// services.mongodb.environment
$mongodb_username = 'root';
$mongodb_password = 'example';
// services.mongodb.container_name
$mongodb_host     = 'ac_mongodb';
// default - don't need to add this to ports in docker-compose
$mongodb_port     = 27017;

$client = new MongoDB\Client(vsprintf(
    'mongodb://%s:%s@%s:%s',
    [
        $mongodb_username,
        $mongodb_password,
        $mongodb_host,
        $mongodb_port,
    ]
));

/** var MongoDB\Collection $client */
$collection = $client
    ->selectDatabase('alistaircol')
    ->selectCollection('policy_data');
```

### **C**reate

I don't have a need to create right now, any future will come in csv.

However, it will just be a case of (with better error handling):

```php
<?php
$document = [
  'k' => 'v',
];
$options = [
  //
];
$collection->insertOne($document, $options);
```

### **R**ead

There are a few things we need to read:

* The distinct values for a particular column, i.e. for filtering, e.g.:
    * Prefix
    * Product
* The number of documents/results in the set matching certain criteria, i.e. for pagination
* A subset of documents/results with subset of fields (projection), i.e. for efficient pagination results
* An individual document to view and update

**All distinct values in column/document key**:

```php
<?php
/**
 * Utility to get all distinct values for $column_name.
 *
 * @param MongoDB\Collection $collection
 * @param string $column_name
 * @return array
 */
function getDistinctValues(MongoDB\Collection $collection, string $column_name): array
{
    $response = $collection->aggregate([
        [
            '$group' => [
                '_id' => sprintf('$%s', $column_name)
            ]
        ],
        [
            '$sort' => [
                '_id' => 1
            ]
        ],
    ]);

    $columns = [];
    foreach ($response as $document) {
        $column = $document->_id;
        $columns[$column] = $column;
    }

    return $columns;
}
```

As the name suggests, this could be used for getting all users/authors or products, etc.

---

**The number of documents/results** matching criteria:

```php
<?php
/**
 * The number of documents in the collection matching $filter criteria.
 * 
 * @param MongoDB\Collection $collection
 * @param array $filter
 * @return int
 */
function queryCollectionCount(MongoDB\Collection $collection, array $filter): int
{
    /** @var ArrayIterator $response */
    $response = $collection->aggregate([
        ['$match' => $filter],
        ['$count' => 'total'],
    ]);

    $response = iterator_to_array($response);
    return $response[0]['total'];
}
```

---

**A subset of documents/results** with projection and other options:

Imagine this is the search page controller logic. From the ui-grid screenshot above, it sets pagination and filter [options](https://docs.mongodb.com/manual/reference/operator/query/regex/#op._S_options).

```php
<?php
$page_size = 20;
$page = 2;
$skip = ($page - 1) * $page_size;

$filters = [
    // Note: The pattern should not be wrapped with delimiter characters.
    'ADDRESS_LINE_1' => (new MongoDB\BSON\Regex('road', 'i')),
    'ADDRESS_POST_CODE' => 'AA1 1AA',
];
```

We will set `projected` to only return what we can display, and set the pagination options.

```php
<?php
$options = [
    // I only want to return these fields
    'projection' => [
        '_id' => true,
        'ADDRESS_LINE_1' => true,
        'ADDRESS_POST_CODE' => true,
        'SURNAME' => true,
        'PREFIX' => true,
        'ENTRY' => true,
        'PRODUCT' => true,
        'CONTRACTOR' => true,
    ],
    'limit' => $page_size,
    'skip' => $skip,
];
```

Easy!

```php
<?php
/**
 * Query $collection for documents matching $filters with $options.
 * 
 * @param MongoDB\Collection $collection
 * @param array $filters
 * @param array $options
 * @return array
 */
function queryDocuments(
    MongoDB\Collection $collection,
    array $filters,
    array $options
): array
{
    $cursor = $collection->find($filters, $options);
    // the _id is stil likely an object of type ObjectId
    // might want to fix that here
    return $cursor->toArray();
}

$documents = queryDocuments($collection, $filter, $options);
```

---

**An individual document to view and update**:

Converted to an `array` instead of an `object` through mostly preference, and I find easier to debug. 

```php
<?php
/**
 * Get a document in the collection with $object_id.
 * 
 * @param MongoDB\Collection $collection
 * @param string $object_id
 * @return array
 */
function getDocument(MongoDB\Collection $collection, string $object_id): array
{
    $response = $collection->findOne(
        [
            '_id' => new MongoDB\BSON\ObjectId($object_id),
        ]
    );

    /** @var BSONDocument $document */
    $document = $response->jsonSerialize();

    $result = (array) $document;
    // convert MongoDB\BSON\ObjectId to string
    $result['_id'] = $object_id;

    return $result;
}
```

This will be the basis for the edit/view page.

### **U**pdate

Update a document, in our case we make a diff and store the diff in MySQL for auditing purposes, omitted for clarity.

```php
<?php
/**
 * Update $old_document to $new_document in $collection.
 *
 * @param Collection $collection
 * @param array $old_document
 * @param array $new_document
 * @return bool
 */
function reviseDocument(
    Collection $collection,
    array $old_document,
    array $new_document
): bool
{
    $object_id = new ObjectId($old_document['_id']);
    $new_document['_id'] = $object_id;

    // TODO: get diff and update in MYSQL DB
    // TODO: restrict certain fields from being changed

    $result = $collection->updateOne(
        [
            '_id' => $object_id
        ],
        [
            '$set' => $new_document
        ]
    );

    // maybe ues $result->getMatchedCount(); instead
    // incase our diff check is crap
    return $result->getModifiedCount() == 1;
}
```

### **D**elete

Currently, we have a soft-delete in place with a cleanup script to hard-delete after a certain time.

To delete from `mongodb`:

```php
<?php
/**
 * Delete $object_id from $collection.
 *
 * @param Collection $collection
 * @param string $object_id
 * @return bool
 */
function deleteDocument(Collection $collection, string $object_id): bool
{
    $response = $collection->deleteOne(
        [
            '_id' => new ObjectId($object_id),
        ]
    );

    return $response->getDeletedCount() == 1;
}
```

Yep, it works.

![app](/img/articles/mongodb-php/mongo-express-deleted.png)
