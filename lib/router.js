'use strict';

const fs        = require('fs');
const httpProxy = require('http-proxy');
const path      = require('path');
const send      = require('send');
const url       = require('url');
const util      = require('util');

const sslCredentials = require('./ssl-credentials');
const configLoader   = require('./load-config');

const pkg = require('../package.json');

util.log(pkg.name + ' v' + pkg.version);

const configFile = path.resolve(process.env.FES_CONFIG || 'etc/router.json');
const configDirectory = path.dirname(configFile);

util.log('Configuration file: ' + configFile);

const config = configLoader.loadFile(configFile);
const serverAgent = config.get('serverAgent') || pkg.name + '/' + pkg.version;

util.log('Server identifier: ' + serverAgent);

const the404Path = config[404] && path.resolve(configDirectory, config['404']) || path.join(__dirname, '..', '404.html');
util.log('No host matched file: ' + the404Path);

const the404 = fs.readFileSync(the404Path);

const serve = function(req, res, proxy, conf) {
  console.log(new Date(), req.headers.host, req.url, '=>',
    conf && conf.target && conf.target.protocol || 404);

  res.setHeader('Server', serverAgent);

  if (!conf) {
    res.setHeader('Content-Type', 'text/html');
    res.setHeader('Content-Length', the404.length);
    res.writeHead(404);
    res.end(the404);
    return;
  }

  req.url = conf.rewrite(req.url);

  if (conf.target.protocol === 'file:') {
    send(req, url.parse(req.url).pathname, { root: conf.target.path }).pipe(res);

  } else if (conf.target.protocol === 'http:') {
    proxy.web(req, res, {
      target: `http://${conf.target.hostname}:${conf.target.port || 80}`
    });

  } else if (conf.target.protocol === 'https:') {
    proxy.web(req, res, {
      target: `https://${conf.target.hostname}:${conf.target.port || 443}`
    });

  } else if (conf.target.protocol === 'redirect:') {
    let parsed = url.parse(req.url);
    parsed.
    parsed.protocol = 'http:';
    let host = [conf.target.hostname];
    if (conf.target.port) {
      host.push(conf.target.port);
    }

    parsed.host = host.join(':');

    res.setHeader('Location', url.format(parsed));
    res.writeHead(302);
    res.end('Redirecting to... ' + url.format(parsed));

  } else if (conf.target.protocol === 'redirects:') {
    let parsed = url.parse(req.url);
    parsed.protocol = 'https:';
    let host = [conf.target.hostname];
    if (conf.target.port) {
      host.push(conf.target.port);
    }

    parsed.host = host.join(':');

    res.setHeader('Location', url.format(parsed));
    res.writeHead(302);
    res.end('Redirecting to... ' + url.format(parsed));

  } else {
    util.log('Server misconfigured, unknown protocol: ' + conf.target.protocol);
    res.writeHead(500);
    res.end('Internal server error');
  }
};

// ##
//  # Lets Encrypt Support
//  ##

let letsEncrypt;
let letsEncryptMiddleware;
if (config.get('ssl') && config.get('ssl').useLetsEncrypt) {
  util.log('Lets Encrypt SSL enabled');

  letsEncrypt = require('greenlock-express').create({
    server: 'staging',
    challenges: {
      'http-01': require('le-challenge-fs').create({
        webrootPath: __dirname + '/../acme-challenges',
      }),
    },
    store: require('le-store-certbot').create({
      webrootPath: __dirname + '/../acme-challenges',
    }),
    approveDomains: (options, certs, cb) => {
      if (certs) {
        options.domains = certs.altnames;
      } else {
        options.email = config.get('ssl').email;
        options.agreeTos = true;
      }
      // check the domains are in our list that we like!
      cb(null, { options, certs });
    }
  });
  letsEncryptMiddleware = (fn) => letsEncrypt.middleware(fn);
} else {
  letsEncryptMiddleware = (fn) => fn;
}

// ##
//  # HTTP
//  ##

const httpServer = httpProxy.createServer(letsEncryptMiddleware((req, res) => {
  serve(req, res, httpServer, config.lookup(req, 'http:', req.url));
}));

httpServer.on('upgrade', function(req, socket, head) {
  httpServer.ws(req, socket, head, config.lookup(req, 'http:'));
});

httpServer.listen(config.getPort('http'), ()=> {
  util.log('HTTP Listening on 0.0.0.0:' + config.getPort('http'));
});

// ##
//  # HTTPS
//  ##

if (config.get('ssl')) {
  if (config.get('ssl').useLetsEncrypt) {
    util.log('SSL enabled, using lets encrypt');

    const httpsServer = httpProxy.createServer(letsEncrypt.httpsOptions,
      letsEncryptMiddleware((req, res) => {
        serve(req, res, httpsServer, config.lookup(req, 'https:'));
      }));

    httpsServer.on('upgrade', (req, socket, head)=> {
      // proxy.ws(req, socket, head);
      const conf = config.lookup(req, 'https:', req.url);
      if (conf.proxyTarget) {
        req.url = conf.rewrite(req.url);
        httpsServer.ws(req, socket, head, { target: conf.proxyTarget });
      } else {
        
      }
    });
    
    httpServer.listen(config.getPort('https'), ()=> {
      util.log('HTTPS Listening ons 0.0.0.0:' + config.getPort('https'));
    });

  } else {
    const defaultSSL = path.resolve(configDirectory, config.get('ssl').default);
    const sslPath = path.resolve(configDirectory, config.get('ssl').location);

    util.log('SSL enabled, default cert: ' + defaultSSL);
    util.log('SSL certificate store: ' + sslPath);

    const ssl = JSON.parse(fs.readFileSync(defaultSSL));

    sslCredentials(sslPath)
      .then(credentials => {

        const httpsServer = httpProxy.createServer({
            https: {
              SNICallback: (hostname, callback) => {
                callback(null, credentials.getCredentialsContext(hostname));
              },

              key: ssl.key,
              cert: ssl.cert,
              ca: ssl.ca
            }
          },
          function(req, res) {
            serve(req, res, httpsServer, config.lookup(req, 'https:'));
          });

        httpsServer.on('upgrade', (req, socket, head)=> {
          // proxy.ws(req, socket, head);
          const conf = config.lookup(req, 'https:', req.url);
          if (conf.proxyTarget) {
            req.url = conf.rewrite(req.url);
            httpsServer.ws(req, socket, head, { target: conf.proxyTarget });
          } else {
            
          }
        });
        
        httpServer.listen(config.getPort('https'), ()=> {
          util.log('HTTPS Listening ons 0.0.0.0:' + config.getPort('https'));
        });
      })
      .catch(function(err) {
        util.log('Unable to read SSL credentials :( ' + err.message);
      });
  }
}

