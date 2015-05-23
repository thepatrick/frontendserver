'use strict';

const dive   = require('dive');
const fs     = require('fs');
const path   = require('path');
const Q      = require('q');
const tls    = require('tls');

const makeCredentialsContext = function(file) {
  return Q.nfcall(fs.readFile, file)
    .then(function(data) {
      return JSON.parse(data);
    }).catch(function(err) {
      throw new Error('Unable to read ' + file + ': ' + err.message);
    }).then(function(json) {
      return tls.createSecureContext(json);
    });
};

const qdive = function(base) {
  let collect = [];
  return new Q.Promise(function(resolve, reject) {
    dive(base, function(err, file) {
      if (err) {
        reject(err);
      } else {
        collect.push(file);
      }
    }, function() {
      resolve(collect);
    });
  });
};

module.exports = function(base) {
  const credentials = {};

  return qdive(base)
    .then(function(toRead) {
      return Q.all(
            toRead.map(function(file) {
              return makeCredentialsContext(file)
                .then(function(secureContext) {
                  credentials[path.basename(file, '.json')] = secureContext;
                });
            })
          );
    })
  .then(function() {
    return {
      getCredentialsContext: function(hostname) {
        // First try for a cert for this hostname
        if (credentials[hostname]) {
          return credentials[hostname];
        }

        // then try a wild card version
        if (credentials[hostname.replace(/^[^\.]+/, '')]) {
          return credentials[hostname.replace(/^[^\.]+/, '')];
        }

        // Returning nothing will use the default context
      }
    };
  });
};
