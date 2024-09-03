---
title: Private Github Readme Stats server and uploading to S3 with Ansible Semaphore
author: Ally
summary: Containerise a private Github Readme Stats server and upload stats card image to S3 using an Ansible playbook on a schedule with Semaphore
publishDate: 2023-09-03T19:50:30+0100
tags: ['github-readme-stats','docker','ansible', 'semaphore']
cover: https://ac93.uk/img/articles/grs/cover.png
---

For some time I've had a [`github-readme-stats`](https://github.com/anuraghazra/github-readme-stats/) stats card in my Github readme profile, and wanted it to include all of my private contributions.

Example:

<center>

![stats](https://static.ac93.uk/github-readme-stats.svg)

</center>


## Containerising the server

Out-of-the box it's geared towards being hosted on Vercel, etc., but they [document](https://github.com/anuraghazra/github-readme-stats/?tab=readme-ov-file#on-other-platforms) running the server by other methods.

```dockerfile
# using alpine doesn't include git
FROM node:18 AS builder
WORKDIR /usr/src
RUN git clone https://github.com/anuraghazra/github-readme-stats.git app
WORKDIR /usr/src/app
# Checkout to specific version
RUN git checkout 30db7790d65053750c0b47e80100f8ddecdbd551
# Install express
RUN npm i --save --package-lock-only express
# Run `ci` install with express included in package file
RUN NODE_ENV=production npm ci --ignore-scripts

FROM node:18-alpine
RUN apk add --no-cache tini
WORKDIR /usr/src/app
COPY --from=builder /usr/src/app ./
EXPOSE 9000

LABEL org.opencontainers.image.source=https://github.com/alistaircol/grs
LABEL org.opencontainers.image.description="Github Readme Stats"
LABEL org.opencontainers.image.licenses=MIT

# Use tini as the entrypoint to handle signals correctly
ENTRYPOINT ["/sbin/tini", "node", "express.js"]
```

Create a [PAT](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic) for pushing/pulling this image, and authenticate.

Using this [`taskfile`](https://taskfile.dev/) to build, tag and push the image.

```yaml
---
version: 3

dotenv:
- .env

vars:
  TAG_DATE:
    sh:
      date +"%Y-%m-%d-%H%M%S"
  IMAGE_NAME: github-readme-stats
  REGISTRY_LOCAL: ac93.uk
  REGISTRY_REMOTE: ghcr.io
  REGISTRY_REMOTE_USER: alistaircol

tasks:
  docker:login:
    silent: true
    cmds:
    - echo "$CR_PAT" | docker login ghcr.io -u {{.REGISTRY_REMOTE_USER}} --password-stdin

  docker:image:build:
    cmds:
    - >-
      docker
      buildx
      build
      --platform linux/amd64,linux/arm64
      --tag {{.REGISTRY_LOCAL}}/{{.IMAGE_NAME}}:{{.TAG_DATE}}
      --tag {{.REGISTRY_LOCAL}}/{{.IMAGE_NAME}}:latest
      --tag {{.REGISTRY_REMOTE}}/{{.REGISTRY_REMOTE_USER}}/{{.IMAGE_NAME}}:{{.TAG_DATE}}
      --tag {{.REGISTRY_REMOTE}}/{{.REGISTRY_REMOTE_USER}}/{{.IMAGE_NAME}}:latest
      .

  docker:image:push:
    cmds:
    - >-
      docker
      push
      --all-tags
      {{.REGISTRY_REMOTE}}/{{.REGISTRY_REMOTE_USER}}/{{.IMAGE_NAME}}
```

## Running the server

Create a `.env` file containing the second [PAT](https://github.com/anuraghazra/github-readme-stats/?tab=readme-ov-file#deploy-on-your-own) for fetching private contributions.

```text
PAT_1=ghp_blah
```

It can be run locally:

```bash
docker run \
    --rm \
    -it \
    --env-file=$(pwd)/.env \
    -p '9000:9000' \
    ac93.uk/github-readme-stats
```

Using the remote image:

```bash
docker run \
    --rm \
    -it \
    --env-file=$(pwd)/.env \
    -p '9000:9000' \
    ghcr.io/alistaircol/github-readme-stats
```

## Appliance

I will be running this GRS server image on an Ubuntu server VM under Proxmox.

It will obviously need `docker` and to be aware of the container registry PAT.

This VM will be the target of the playbook so will need some [AWS dependencies](https://docs.ansible.com/ansible/latest/collections/amazon/aws/s3_object_module.html#requirements). A truncated setup role could look like this:

```yaml
---
- name: Install required system packages
  become: true
  block:
  - name: Update apt caches
    ansible.builtin.apt:
      update_cache: true

  - name: Install required system packages
    ansible.builtin.package:
      name:
      - python3
      - python3-pip
      state: present

  - name: Install aws dependencies for ansible playbooks
    ansible.builtin.pip:
      name:
      - botocore
      - boto3
```

## Playbook

The playbook will look relatively simple to:

* Create a temporary directory
* Download image from local private GRS server to temporary directory
* Upload image in temporary directory to S3

```yaml
---
- name: Create a private Github readme stats and upload them
  hosts:
  - grs
  gather_facts: false

  tasks:
  - name: Create a temporary directory
    ansible.builtin.tempfile:
      state: directory
      suffix: grs
    register: tmpdir

  - name: Download Github readme stats image
    ansible.builtin.get_url:
      url: http://192.168.1.97:9000/?username=alistaircol&count_private=true&show_icons=true&custom_title=Ally+on+GitHub&disable_animations=true&title_color=58a6ff&icon_color=ffffff&text_color=ffffff&bg_color=0D1117&border_color=30363D&hide=issues,contribs,stars&show=prs_merged,reviews
      dest: "{{ tmpdir.path }}/github-readme-stats.svg"
    register: downloaded_image

  - name: Upload the image to S3
    amazon.aws.aws_s3:
      access_key: "{{ lookup('ansible.builtin.vars', 'AWS_ACCESS_KEY_ID') }}"
      secret_key: "{{ lookup('ansible.builtin.vars', 'AWS_ACCESS_KEY') }}"
      region: "{{ lookup('ansible.builtin.vars', 'AWS_REGION') }}"
      bucket: static.ac93.uk
      object: github-readme-stats.svg
      src: "{{ downloaded_image.dest }}"
      mode: put
```

## Semaphore

Create a project in [semaphore](https://semaphoreui.com/) then follow these instructions.

### Key Store

Create a new key entry so that the workers can connect to the target.

<center>

![key store](/img/articles/grs/semaphore-key.png)

</center>


### Inventory

Create a new `static-yaml` inventory.

```yaml
---
all:
  vars:
    ansible_host_key_checking: false
  hosts:
    grs:
      ansible_host: 192.168.1.97
      ansible_user: ally
```

<center>

![inventory](/img/articles/grs/semaphore-inventory.png)

</center>

### Repository

Add the `git` repository where the playbook lives. You might need to create a new key in the store.

### Environment

Create a new environment, we will add our AWS credentials here so the playbook can read them and pass to the target.

Add the AWS credentials to the `Extra variables` section.

<center>

![environment](/img/articles/grs/semaphore-environment.png)

</center>


### Task Template

Create a new task template.

* Set the repository to the one created earlier
* Set the playbook file as a relative path to it within the repo
* Set the inventory to the `static-yaml` one created earlier
* Set the environment to the one created earlier containing the AWS credentials in `Extra variables`
* Set the cron to `0 0 * * *` to run every day at midnight

<center>

![template](/img/articles/grs/semaphore-task.png)

</center>

You can see the run history:

<center>

![template](/img/articles/grs/semaphore-runs.png)

</center>

You can interrogate previous runs:

<center>

![template](/img/articles/grs/cover.png)

</center>
