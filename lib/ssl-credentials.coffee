async  = require 'async'
crypto = require 'crypto'
dive   = require 'dive'
fs     = require 'fs'
path   = require 'path'

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
          @credentials[path.basename(file, ".json")] = crypto.createCredentials(json).context
          cb()


  getCredentialsContext: (cer)->
    @credentials[cer]

module.exports = (@base, callback)->
  new SSLCredentials @base, callback