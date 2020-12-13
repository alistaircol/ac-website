---
title: "Scraping legacy static sites and hosting them (yuck!)"
author: "Ally"
summary: "This was hell. Just an excuse to save some handy `wget`, `ssh`, `find`, `csvtool`, `xargs`, commands and other occasionally useful things, honestly."
publishDate: 2020-07-14T12:00:00+01:00
tags: ['php', 'wget', 'csv', 'httpd', 'cloudflare']
draft: false
---

## Mirroring sites with `wget`

For this, there is a list of subdomains in `sites.csv` 3rd column (counting from 1), not too important but just to explain the format for `csvtool`.

We drop first row because this is header names and pass the rest in. For each row in the csv file we run the `wget` command.

```shell script
csvtool drop 1 sites.csv \
    | csvtool format '%(3)\n' - \
    | xargs -L1 wget -mkEpnp "'{}'"
```

`wget` flags: `-mkEpnp` explained:

* `-m,  --mirror                    shortcut for -N -r -l inf --no-remove-listing`
    * `-N,  --timestamping              don't re-retrieve files unless newer than local`
    * `-r,  --recursive                 specify recursive download`
    * `-l,  --level=NUMBER              maximum recursion depth (inf or 0 for infinite)`
    * `--no-remove-listing              don't remove '.listing' files`
* `-p,  --page-requisites           get all images, etc. needed to display HTML page`
* `-k,  --convert-links             make links in downloaded HTML or CSS point to local files`
*  `-np, --no-parent                don't ascend to the parent directory`

With all sites downloaded locally, you might need to do some `sed` things. I know I did. For example: replacing hardcoded protocols, i.e. upgrading `http` -> `https` references (which Cloudflare might not rewrite for you), or domains which may be renamed, disabling certain URLs on sites, etc.

Ideally I wanted to use some `dom` manipulation in PHP, but argh! the source markup was a dog's dinner.

A freebie for zipping up all the folders in the current directory:

```shell script
find . \
    -maxdepth 1 \
    -type d \
    ! -path . \
    -exec zip -r $(basename {}).zip $(basename {}) \;
```

## Install & Configure Server

Used the following commands to set up a fresh Ubuntu 20.04 server from DigtalOcean.

**Note:**: You do not need to follow this section if you use Amazon Linux AMI. Maybe DO with SSH keys does something equivalent.

```shell script
apt update
apt upgrade
# set password to whatever you want
adduser ubuntu
# apache logs are adm group
usermod -aG sudo ubuntu
usermod -aG adm ubuntu
# for passwordless sudoing
cat <<EOF >> /etc/sudoers
ubuntu ALL=(ALL) NOPASSWD: ALL
EOF
su ubuntu
cd /home/ubuntu
mkdir /home/ubuntu/.ssh
chmod -R 700 /home/ubuntu/.ssh
touch /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
# add developers public key
cat <<EOF >> /home/ubuntu/.ssh/authorized_keys
ssh-rsa [redacted_key] [redacted_user]
EOF
# some utilities to get going with next steps
sudo apt-get install -y software-properties-common git pv nano htop vim jq neofetch mlocate
```

### PHP

Installing Apache, PHP on the server (as `root`):

```shell script
add-apt-repository ppa:ondrej/apache2 -y
apt install -y apache2
a2enmod headers
a2enmod rewrite
systemctl restart apache2

add-apt-repository -y ppa:ondrej/php
apt-get install -y php7.4 php7.4-common libapache2-mod-php7.4

# verify
/usr/sbin/apache2 -v
php -v

chown -R ubuntu:ubuntu /var/www
```

### Email

Had to reverse-engineer the legacy sites backend contact form. Won't bore you with that code because it's super simple.

Ugh I hate emails, but is a necessary evil. Testing `mail()` call gave this (`tail -f /var/log/apache2/error.log`):

```text
sh: 1: /usr/sbin/sendmail: not found
```

That's no good.

```shell script
# for php mail function
apt install postfix
```

While it is installing, it will ask you a couple of questions. For my scenario I answered the following:

* Internet site: Mail is sent and received directly using SMTP.
* The "mail name" is the domain name used to "qualify" ALL mail addresses without a domain name.
    * `ac93.uk`

If this ever needs changed:

```shell script
nano /etc/postfix/main.cf
systemctl reload postfix
```

Might need to tweak `sendmail_path` to give correct sender information in php.ini:

```shell script
$ locate php.ini
/etc/php/7.4/apache2/php.ini
/etc/php/7.4/cli/php.ini
/usr/lib/php/7.4/php.ini-development
/usr/lib/php/7.4/php.ini-production
/usr/lib/php/7.4/php.ini-production.cli

nano /etc/php/7.4/apache2/php.ini
```

set the `sendmail_path` to:

```text
sendmail -ti -F Ally -f contact@ac93.uk
```

With this just as `sendmail -ti`, even if I specified the sender in `mail()` call, it would send the servers hostname as the envelope's sender address.

The `sendmail` flags:

```text
-t Read message for recipients. To:, Cc:, and Bcc: lines will be scanned for recipient addresses. The Bcc: line will be deleted before transmission.
-i Ignore dots alone on lines by themselves in incoming messages. This should be set if you are reading data from a file.

-Ffullname Set the full name of the sender.
-fname     Sets the name of the 'from' person (i.e., the envelope sender of the mail).
```

and reload

```shell script
systemctl reload apache2
```

**Tip:** For email to be a bit more secure and for some clients to determine authenticity the IP needs to be added to domain [SPF Record](https://support.google.com/a/answer/33786?hl=en), this is a TXT record. Just adding because it was relevant for me!


### `httpd` Virtual Hosts

Similar to the first command, we take the `sites.csv` and create the virtual host based on that.

```shell script
#!/usr/bin/env bash
csvtool drop 1 sites.csv | csvtool format '%(3)\n' - | while read domain; do
cat <<EOF > /etc/apache2/sites-available/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@ac93.org
    ServerName $domain
    DocumentRoot /var/www/html/$domain/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/html/$domain>
        Options -Indexes
        RewriteEngine On
        AllowOverride None
    </Directory>
</VirtualHost>
EOF

sudo a2ensite $domain

done

sudo systemctl reload apache2
```

This should only be run once, since you might need to make a tweak to an individual host and if ran a second time this tweak would be lost.

### Git

Login to server as `ubuntu`.

```shell script
ssh-keygen -t rsa -N '' -f /home/ubuntu/.ssh/id_rsa
cat /home/ubuntu/.ssh/id_rsa.pub
```

The static sites have been thrown into a repository.

For the server to access this, copy the `id_rsa.pub` from the server and add the SSH key. In Bitbucket: Go to repository → repository settings → access keys.

Clone the repo in `/var/www/html`.

## Wildcard Subdomain & Cloudflare

The subdomains are routed to a server using a wildcard subdomain, unfortunately these cannot be proxied through Cloudflare, and we do not see many benefits.

I found the easiest way to do this was to export the DNS records and update the file manually, and import it again.
