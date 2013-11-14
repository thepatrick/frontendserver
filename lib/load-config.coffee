fs   = require 'fs'
path = require 'path'
url  = require 'url'
util = require 'util'

first = (arr, match)->
  matched = null
  arr.some (item)->
    if match(item)
      matched = item
      true
  matched

module.exports.loadFile = (configPath)->

  json = null
  config = null

  reloadConfig = (done)->

    incoming = fs.readFileSync configPath

    try
      json = JSON.parse incoming
    catch err
      return done Error "Error parsing config: " + err.message

    unless json.routes?
      done Error "No routes block in " + configPath

    config =
      "http:": {}
      "https:": {}
      "default:": {}

    for own _match, directive of json.routes
      match = url.parse _match
      unless config[match.protocol]?
        util.log "Invalid match protocol " + match.protocol + " in route " + _match
      else
        host = (config[match.protocol][match.host] ||= { byPath: [] })
        target = url.parse directive
        targetProtocol = target.protocol.split '+'
        target.protocol = targetProtocol.pop()
        targetProtocol.forEach (protoModifier)->
          target[protoModifier] = true

        if match.pathname && match.pathname != "/"
          host.byPath.push path: match.pathname, target: target
        else
          host.default = url.parse directive

  lookup = (proto, host, pathname)->
    # does this proto/host have any byPath?
    host = config[proto][host]
    if host?
      if host.byPath.length > 0
        match = first host.byPath, (byPath)->
          console.log 'compare', pathname.substring(0, byPath.path.length) == byPath.path
          pathname.substring(0, byPath.path.length) == byPath.path
      if match?
        console.log match
        match =
          _path: match.path
          target: match.target
          rewrite: (reqUrl)->
            if @target.nopath
              "/"
            else if @target.nostrippath
              reqUrl
            else
              path.join "/", reqUrl.substring(@_path.length)
      else
        match = 
          target: host.default
          rewrite: (reqUrl)-> 
            if @target.nopath
              "/"
            else
              reqUrl

      console.log 'match', match
      match

  reloadConfig()

  get: (key)->
    json[key]

  reloadRoutes: (done)->
    reloadConfig done

  lookup: (req, proto)->
    host = req.headers.host?.split(":")[0]
    reqUrl = url.parse req.url
    pathname = reqUrl.pathname

    # Try the hostname first
    lookup(proto, host, pathname) || 
    # Then try the wildcard hostname that would match this
    lookup(proto, host.replace(/^[^\.]+/,""), pathname) ||
    # Then default
    lookup("default:", proto.substring(0,proto.length-1), pathname)
