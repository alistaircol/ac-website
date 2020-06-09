---
title: "HTTPD Server Configuration Hardening"
author: "Ally"
summary: "Some tips I picked up to make sites hosted on `httpd` servers more secure."
publishDate: 2020-06-10T12:00:00+01:00
tags: ['httpd']
draft: true
---

Some things from a security audit that were brought up and can effect many sites by default.

## Deprecated Encryption Protocol & Cipher

**Test**:

```bash
nmap --script ssl-enum-ciphers \
    -p 443 \
    website.com 
```

**Result**:

```text
Starting Nmap 7.80 ( https://nmap.org ) at 2020-06-09 09:45 BST
Nmap scan report for [redacted]
Host is up (0.023s latency).
Other addresses for [redacted] (not scanned): [redacted]

PORT    STATE SERVICE
443/tcp open  https
| ssl-enum-ciphers: 
|   TLSv1.0: 
|     ciphers: 
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA (rsa 2048) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA (rsa 2048) - A
|       TLS_RSA_WITH_3DES_EDE_CBC_SHA (rsa 2048) - C
|     compressors: 
|       NULL
|     cipher preference: server
|     warnings: 
|       64-bit block cipher 3DES vulnerable to SWEET32 attack
|   TLSv1.1: 
|     ciphers: 
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA (rsa 2048) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA (rsa 2048) - A
|     compressors: 
|       NULL
|     cipher preference: server
|   TLSv1.2: 
|     ciphers: 
|       TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256-draft (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256-draft (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA (rsa 2048) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_128_GCM_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_GCM_SHA384 (rsa 2048) - A
|     compressors: 
|       NULL
|     cipher preference: client
|_  least strength: C

Nmap done: 1 IP address (1 host up) scanned in 2.37 seconds
```

**Result**:

The systems support a deprecated TLS encryption protocol and associated cipher.

The cryptographic protocols and ciphers supported by some applications can undermine the secure communication between the server and the client.

**Remediation**:

The easy way, following https://httpsiseasy.com/
 
- Disable the use of TLS v1.0 encryption protocol
- Disable the use of DES encryption cipher.

Basically enabling TLS 3, and setting minimum TLS version to TLS 1.2. (TLS 1.3 support is [good](https://caniuse.com/#feat=tls1-3) but not massive).

> Go to SSL/TLS -> Edge Certificates

![Enable TLS 1.3](/img/articles/httpd-server-hardening/tls1-3.png)

![Set Minimum TLS 1.2](/img/articles/httpd-server-hardening/minimum-tls.png)

Now run the script again with these changes:

```text
Starting Nmap 7.80 ( https://nmap.org ) at 2020-06-09 10:19 BST
Nmap scan report for [redacted]
Host is up (0.019s latency).
Other addresses for [redacted] (not scanned): [redacted]

PORT    STATE SERVICE
443/tcp open  https
| ssl-enum-ciphers: 
|   TLSv1.2: 
|     ciphers: 
|       TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256-draft (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 (ecdh_x25519) - A
|       TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256-draft (ecdh_x25519) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA (rsa 2048) - A
|       TLS_RSA_WITH_AES_128_CBC_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_128_GCM_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_CBC_SHA256 (rsa 2048) - A
|       TLS_RSA_WITH_AES_256_GCM_SHA384 (rsa 2048) - A
|     compressors: 
|       NULL
|     cipher preference: client
|_  least strength: A

Nmap done: 1 IP address (1 host up) scanned in 1.96 seconds
```

Alternatively: https://www.ssllabs.com/ssltest/

## Information Disclosure

**Reason**:

Information about the backend server and associated system is exposed through error disclosure. This may allow an attacker to perform tailored attacks against such components if found vulnerable.

**Result**:

Server responses may reveal information about the version of the backend system components.

**Remediation**:

Edit the server version value from the response header and create a custom error page, so that should any error occur, the custom page will be displayed rather than the default error messages.

Source:

* https://www.tecmint.com/hide-apache-web-server-version-information/

Add to top of a config file, e.g.:

`/etc/apache2/sites-available/000-default.conf`

```text
ServerTokens Prod
ServerSignature Off
```

More info on:

* [`ServerTokens`](https://httpd.apache.org/docs/2.4/mod/core.html#servertokens)
* [`ServersSignature`](https://httpd.apache.org/docs/2.4/mod/core.html#serversignature)

TODO: screenshots with each of these options enabled.

| `ServerTokens Full` (default) | `ServerTokens Prod` |
|-------------------------------|---------------------|
| TODO                          | TODO                |

`apache2ctl configtest` and `systemctl reload apache2` if all good.

Adding extra security headers.

Source:

* https://securityheaders.com/

```bash
sudo a2enmod headers
sudo systemctl restart apache2
sudo apache2ctl configtest
```

Within the `<VirtualHost>` directive of a config file, e.g.:

```text
Header always set Strict-Transport-Security "max-age=63072000; includeSubdomains;"
Header always set X-Frame-Options "deny"
Header always set X-Content-Type-Options "nosniff"
Header always set Referrer-Policy "same-origin"
```

More info on:

* [`Header`](https://httpd.apache.org/docs/2.4/mod/mod_headers.html#header)

Summary of suggested headers from [securityheaders.com](https://securityheaders.com):

* `Strict-Transport-Security`
    * [HTTP Strict Transport Security](https://scotthelme.co.uk/hsts-the-missing-link-in-tls/) (HSTS) is an excellent feature to support on your site and strengthens your implementation of TLS by getting the User Agent to enforce the use of HTTPS.
    * Recommended value `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
* [`Content-Security-Policy`](https://scotthelme.co.uk/content-security-policy-an-introduction/)
    * Is an effective measure to protect your site from XSS attacks. By whitelisting sources of approved content, you can prevent the browser from loading malicious assets.
* [`X-Frame-Options`](https://scotthelme.co.uk/hardening-your-http-response-headers/#x-frame-options)
    * Tells the browser whether you want to allow your site to be framed or not. By preventing a browser from framing your site you can defend against attacks like clickjacking. Recommended value `X-Frame-Options: SAMEORIGIN`.
* [`X-Content-Type-Options`](https://scotthelme.co.uk/hardening-your-http-response-headers/#x-content-type-options)
    * Stops a browser from trying to MIME-sniff the content type and forces it to stick with the declared content-type. The only valid value for this header is `X-Content-Type-Options: nosniff`.
* [`Referrer-Policy`](https://scotthelme.co.uk/a-new-security-header-referrer-policy/)
    * Is a new header that allows a site to control how much information the browser includes with navigations away from a document and should be set by all sites.
* [`Feature-Policy`](https://scotthelme.co.uk/a-new-security-header-feature-policy/)
    * Is a new header that allows a site to control which features and APIs can be used in the browser.
* [`Expect-CT`](https://scotthelme.co.uk/a-new-security-header-expect-ct/)
    * Allows a site to determine if they are ready for the upcoming Chrome requirements and/or enforce their CT policy.

Verify the results:

```text
$ curl --include --location --head website.com
HTTP/2 200 
date: Tue, 09 Jun 2020 10:05:19 GMT
content-type: text/html; charset=UTF-8
set-cookie: __cfduid=[redacted]; expires=Thu, 09-Jul-20 10:05:19 GMT; path=/; domain=[redacted]; HttpOnly; SameSite=Lax
strict-transport-security: max-age=63072000; includeSubdomains;
x-frame-options: deny
x-content-type-options: nosniff
referrer-policy: same-origin
cache-control: no-cache, private
cf-cache-status: DYNAMIC
cf-request-id: [redacted]
expect-ct: max-age=604800, report-uri="https://report-uri.cloudflare.com/cdn-cgi/beacon/expect-ct"
server: cloudflare
cf-ray: [redacted]
```

Harder to see, but can try and come up with some screenshots for this.

---

Some `nmap` things.

> yq: Command-line YAML/XML processor - jq wrapper for YAML and XML documents

```bash
sudo apt install jq
pip3 install yq

nmap -Ox out.xml ..
cat out.xml | xq '.nmaprun.host.ports.port.script'
```
