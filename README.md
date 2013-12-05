frontendserver
==============

A wrapper around node-http-proxy, to make it easier to use with name-based SSL.

Running
-------

See configuration first. Then from the frontendserver directory run `node bin/router.js`

In the `launch` directory you'll find scripts/configuration files for various systems. (Currently only launchd).

Configuration
-------------

By default is in etc/router.json. To load something else use the `FES_CONFIG=` environment variable. (Either use an absolute path or relative to the working directory when you start frontendserver.)

A bare bones file etc/router.json.sample is included with frontendserver. Copy it to etc/router.json to get started.

router.json
-----------

All paths are relative to the path router.json is loaded from (or use an absolute path).

* `ports` to listen for HTTP/HTTPS on different ports set this (default: `{"ports": { "http": 8080, "https": 8443 }}`)

* `routes` see directions below

* `serverAgent` if you want to override the default Server: HTTP header.

* `ssl` include this key to enable the SSL server, see directions below.

routes
------

Routes are the mappings from incoming protocol + host name pairings to either remote (proxied) HTTP/HTTPS servers, redirects or local file system paths.

A typical routes key looks like:

```
{
  "routes": {
    "http://test1/": "http://127.0.0.1:9999/",
    "http://test2/": "https://127.0.0.1:9998/",
    "http://test3/": "redirect://test1/",
    "http://test4/": "file:///var/www/test4/",
    "default://http": "file://var/www/default/"
  }
}
```

We'll cover those line by line.

**`"http://test1/": "http://127.0.0.1:9999/"`**

Proxies HTTP requests with the host name "test1" using HTTP to 127.0.0.1:9999. (Note the port we are listening on is ignored when comparing the hostname to test1).

**`"http://test2/": "https://127.0.0.1:9998/"`**

Proxies HTTP requests with the host name "test2" using HTTPS to 127.0.0.1:9998. (Note the port we are listening on is ignored when comparing the hostname to test1).

**`"http://test3/": "redirect://test1/"`**

Redirects HTTP requests from `http://test3/` to `http://test1/`. The path/query string are preserved (e.g. `http://test3/search?q=Hello` will redirect to `http://test1/search?q=Hello`)

**`"http://test4/": "file:///var/www/test4/"`**

Requests to `http://test4/` will be served directly by frontendserver from `/var/www/test4/`.

**`"default://http": "file://var/www/default/"`**

Requests that over HTTP that are not matched by one of the other records will be served by this rule, here by serviing files from `/var/www/default`. It could just as easily be a redirect or a proxy rule though!

SSL
---

frontendserver supports SNI to provide name based routing over SSL. 

To simply configuration you'll need to package the key, certificate any chained authority certificates into an SSL bag.

To create an SSL bag:

```
$ coffee /path/to/frontendserver/lib/package-ssl.coffee --key path/to/ssl.key --cert path/to/ssl.certificate --ca path/to/first-authority.cert --ca path/to/second-authority.cert --out mybag.json
```

The SSL configuration looks like:

```
{
  "ssl": {
    "default": "ssl/default.json",
    "location": "ssl/"
  }
}
```

* `default` is the SSL bag to use by default.
* `location` is a folder with additional SSL bags to load. Each bag should be named "hostname.json". (Yes, this means frontendserver doesn't support wildcard certificates very well right now.)

Licence
-------

The MIT License (MIT)

Copyright (c) 2013 Patrick Quinn-Graham

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
