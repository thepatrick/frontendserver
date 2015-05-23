'use strict';

const fs   = require('fs');
const path = require('path');
const url  = require('url');
const util = require('util');
const _    = require('lodash');

const joinURLs = function(before, after) {
  if (before[before.length - 1] === '/' && after[0] === '/') {
    return before + after.substring(1);

  } else if (before[before.length - 1] === '/' || after[0] === '/') {
    return before + after;

  } else {
    return before + '/' + after;
  }
};

const defaultPorts = {
  http: 80,
  https: 443
};

exports.loadFile = function(configPath) {

  let json;
  let config;

  var reloadConfig = function() {
    const incoming = fs.readFileSync(configPath);

    try {
      json = JSON.parse(incoming);
    } catch (err) {
      throw new Error('Error parsing config: ' + err.message);
    }

    if (!json.routes) {
      throw new Error('No routes block in ' + configPath);
    }

    config = {
      'http:': {},
      'https:': {},
      'default:': {}
    };

    Object.keys(json.routes).forEach(function(rawMatch) {
      const match = url.parse(rawMatch);
      const directive = json.routes[rawMatch];
      
      if (!config[match.protocol]) {
        util.log('Invalid match protocol ' + match.protocol + ' in route ' + rawMatch);

      } else {
        if (!config[match.protocol][match.host]) {
          config[match.protocol][match.host] = { byPath: [] };
        }

        const host = config[match.protocol][match.host];
        const target = url.parse(directive);
        const targetProtocol = target.protocol.split('+');
        target.protocol = targetProtocol.pop();
        targetProtocol.forEach(function(protoModifier) {
          target[protoModifier] = true;
        });

        if (target.protocol === 'file:') {
          try {
            if (fs.statSync(target.path).isFile()) {
              target.isFile = path.basename(target.path);
              target.pathname = target.path = path.dirname(target.path);
            }
          } catch (err) {
            throw new Error('Error verifying ' + target.path + ': ' + err.message);
          }
        }

        if (match.pathname && match.pathname !== '/') {
          host.byPath.push({ path: match.pathname, target: target });
        } else {
          console.log('setting host.target => ', target);
          host.default = target;
        }

      }
    });
  };

  const lookup = function(proto, hostname, pathname) {
    const host = config[proto][hostname];
    if (host) {

      let match = _.first(host.byPath, (byPath)=> {
        return pathname.substring(0, byPath.path.length) === byPath.path;
      });

      if (match) {
        match = {
          matchPath: match.path,
          target: match.target,
          rewrite: function(reqUrl) {
            var targetPathBase;
            if (this.target.protocol === 'file:' && this.target.isFile) {
              return this.target.isFile;
            } else {
              if (this.target.protocol === 'file:') {
                targetPathBase = '/';
              } else {
                targetPathBase = this.target.pathname;
              }

              if (this.target.nopath) {
                return this.target.pathname;
              } else if (this.target.nostrippath) {
                return joinURLs(targetPathBase, reqUrl);
              } else {
                return joinURLs(targetPathBase, reqUrl.substring(this.matchPath.length));
              }
            }
          }
        };
      } else {
        match = {
          target: host.default,
          matchPath: '/',
          rewrite: function(reqUrl) {
            var targetPathBase = this.target.protocol === 'file:' ? '/' : this.target.pathname;
            if (this.target.nopath) {
              return targetPathBase;
            } else if (this.target.nostrippath) {
              return joinURLs(targetPathBase, reqUrl);
            } else {
              return joinURLs(targetPathBase, reqUrl.substring(this.matchPath.length));
            }
          }
        };

      }

      return match;
    }
  };

  reloadConfig();

  return {

    getPort(proto) {
      return json.ports && json.ports[proto] || defaultPorts[proto];
    },

    get(key) {
      return json[key];
    },

    lookup(req, proto) {
      const host = req.headers.host && req.headers.host.split(':')[0];
      const reqUrl = url.parse(req.url);
      const pathname = reqUrl.pathname;

      // Try the hostname first
      return lookup(proto, host, pathname) ||

        // Then try the wildcard hostname that would match this
        lookup(proto, host.replace(/^[^\.]+/, ''), pathname) ||

        // Then default
        lookup('default:', proto.substring(0, proto.length - 1), pathname);
    }

  };

};
