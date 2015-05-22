async  = require 'async'
dive   = require 'dive'
fs     = require 'fs'
path   = require 'path'
tls    = require 'tls'

class SSLCredentials

  constructor: (@base, ready)->
    @credentials = {}
    toRead = []
    dive @base, (err, file)->
      if err
        ready err
      toRead.push file
    , =>
      async.forEach toRead, (item, cb)=>
        @makeCredentialsContext item, cb
      , ready

  makeCredentialsContext: (file, cb)->
    fs.readFile file, (err, data)=>
      if err
        cb Error "Error reading " + file + ": " + err.message
      else
        try
          json = JSON.parse data
        catch _err
          err = _err
        if err || !json
          cb Error "Error reading " + file + ": " + err?.message || "Invalid data"
        else
          @credentials[path.basename(file, ".json")] = tls.createSecureContext(json)
          cb()


  getCredentialsContext: (cer)->
    # Frist try for a cert for this hostname
    @credentials[cer] ||
    # Then try for a cert for a wildcard version of this hostname
    @credentials[cer.replace(/^[^\.]+/,"")]
    # Returning null will use the default credentials

module.exports = (@base, callback)->
  new SSLCredentials @base, callback
