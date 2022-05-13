---
title: "PHP code analysis with Sonarqube in Docker"
author: "Ally"
summary: "Code Quality and Security - SonarQube empowers all developers to write cleaner and safer code."
publishDate: 2020-11-08T12:00:00+01:00
tags: ['php', 'docker', 'sonarqube']
draft: false
---

[Sonarqube](https://docs.sonarqube.org/latest/) is a code analysis tool.

The Sonarqube stack is fairly simple and can be found on its [docs](https://docs.sonarqube.org/latest/) and [Github](https://github.com/SonarSource/docker-sonarqube/tree/master/example-compose-files).

`docker-compose.yml`:

```yaml
version: "2"

services:
  sonarqube:
    image: sonarqube:8.2-community
    container_name: sonarqube
    depends_on:
      - db
    ports:
      - "9000:9000"
    networks:
      - sonarnet
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_temp:/opt/sonarqube/temp

  db:
    image: postgres
    networks:
      - sonarnet
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar
    volumes:
      - postgresql:/var/lib/postgresql
      # This needs explicit mapping due to
      # https://github.com/docker-library/postgres/blob/4e48e3228a30763913ece952c611e5e9b95c8759/Dockerfile.template#L52
      - postgresql_data:/var/lib/postgresql/data

networks:
  sonarnet:

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  sonarqube_temp:
  postgresql:
  postgresql_data:
```

## Sonarqube

Run the stack with

```shell script
docker-compose up -d

# or alternative docker-compose.yml file name
docker-compose -f alternative-name.yml up -d
```

If you get the error:

```text
 max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

[Solution](https://stackoverflow.com/a/51448773/5873008), run on host machine:

```shell script
sudo sysctl -w vm.max_map_count=262144
sudo sysctl --system
```

and then run `docker-compose up` again.

---

Go to `http://localhost:9000` and get started.

![Starting](/img/articles/sonarqube/01-starting.png)

![No Projects](/img/articles/sonarqube/02-no-projects.png)

![Login](/img/articles/sonarqube/03-login.png)

Login using `admin` for username and `admin` for password.

![Projects](/img/articles/sonarqube/04-welcome.png)

To analyse the project we need to create it in Sonarqube, so, create it and a token.

![Create Project](/img/articles/sonarqube/05-create-project.png)

![Create Token](/img/articles/sonarqube/06-create-token.png)

Copy this token - we will need it when running the scanner on the code.

![Token Added](/img/articles/sonarqube/07-token-added.png)

![Projects](/img/articles/sonarqube/08-projects.png)

## Sonar Scanner

Running analysis:

```shell script {linenos=true, hl_lines=[6,7,13,15]}
docker rm --force sonar_scanner; \
  docker run \
    --tty \
    --interactive \
    --volume="$(pwd):/usr/src" \
    --network="host" \
    --name="sonar_scanner" \
    newtmitch/sonar-scanner \
    -X \
    -Dsonar.projectKey=test \
    -Dsonar.sources=. \
    -Dsonar.host.url=http://127.0.0.1:9000 \
    -Dsonar.login=43c74d57f41b288b1227ec144406ce39f2cf7122 \
    -Dsonar.verbose=true \
    -Dsonar.scm.disabled=true \
    -Dsonar.exclusions='Vendor/**, app/Vendor/**, build/**, node_modules/**' \
    -Dsonar.inclusions='**/*.php'
```

* Line number 6 will change the network mode, adding `network=sonarnet` does not hook into that network. Instead, the `host` option for `network` acts like you would imagine given the name.
* Line number 7 is important. Without this, the scanner is unable to send its analysis to the server.
* Line number 13 will need to be changed to use your token generated.
* Line number 15 is also important. Without this, I was unable to run the scanner.
* Line numbers 16 and 17 are important to exclude any vendor files you have no real control over, and exclude other files that might not be relevant to reduce clutter and speed up scanning.

Read more about the options for sonar scanner [here](https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/).

The scanner might take some time to complete!

```text
09:45:46.291 DEBUG: Post-jobs :
09:45:46.374 DEBUG: stylelint-bridge server will shutdown
09:45:46.383 INFO: Analysis total time: 1:29.383 s
09:45:46.437 INFO: --------------------------------------
09:45:46.438 INFO: EXECUTION SUCCESS
09:45:46.439 INFO: --------------------------------------
09:45:46.441 INFO: Total time: 1:36.495s
09:45:46.550 INFO: Final Memory: 14M/50M
09:45
```

![Scan Complete](/img/articles/sonarqube/09-scan-complete.png)

![Errors](/img/articles/sonarqube/10-errors.png)

Very handy to know these things!

![Quality](/img/articles/sonarqube/11-quality.png)
