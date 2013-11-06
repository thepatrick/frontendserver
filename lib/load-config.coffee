fs   = require 'fs'
path = require 'path'
url  = require 'url'

module.exports.loadFile = (path)->

  incoming = fs.readFileSync path
  json = JSON.parse incoming

  unless json.routes?
    throw Error "No routes block in " + path

  config = {}

  for own match, directive of json.routes
    match = url.parse match
    config[match.protocol] ||= {}
    config[match.protocol][match.host] = url.parse directive

  json.routes = config
  json
