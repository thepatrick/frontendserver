'use strict';

const dive   = require('dive');
const fs     = require('fs');
const path   = require('path');
const tls    = require('tls');

const {promisify} = require('util');

const readFileAsync = promisify(fs.readFile); // (A)

const makeCredentialsContext = async function(file) {
  const data = await readFileAsync(file);
  let json;
  try {
    json = JSON.parse(data);
  } catch (err) {
    throw new Error('Unable to read ' + file + ': ' + err.message); 
  }
  return tls.createSecureContext(json);
};

const qdive = function(base) {
  let collect = [];
  return new Promise(function(resolve, reject) {
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

module.exports = async function(base) {
  const credentials = {};

  const roRead = await qdive(base);

  await Promise.all(toRead.map((file) => 
     makeCredentialsContext(file)
      .then(function(secureContext) {
        credentials[path.basename(file, '.json')] = secureContext;
      })
  ));

  return {
    getCredentialsContext: function(hostname, callback) {
      // First try for a cert for this hostname
      if (credentials[hostname]) {
        callback(null, credentials[hostname]);
      }

      // then try a wild card version
      if (credentials[hostname.replace(/^[^\.]+/, '')]) {
        callback(null, credentials[hostname.replace(/^[^\.]+/, '')]);
      }

      // Returning nothing will use the default context
      callback();
    }
  };
};
