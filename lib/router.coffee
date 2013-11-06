fs        = require 'fs'
httpProxy = require 'http-proxy'
http      = require 'http'
path      = require 'path'
send      = require 'send'
url       = require 'url'
util      = require 'util'

sslCredentials = require './ssl-credentials'
configLoader   = require './load-config'

pkg = JSON.parse fs.readFileSync path.join __dirname, "..", "package.json"

util.log pkg.name + " v" + pkg.version

configFile = path.resolve process.env.FES_CONFIG || "etc/router.json"
configDirectory = path.dirname configFile
util.log "Configuration file: " + configFile

config = configLoader.loadFile configFile

serverAgent = config.serverAgent || pkg.name + "/" + pkg.version
util.log "Server identifier: " + serverAgent

lookup = (req, proto)->
  host = req.headers.host?.split(":")[0]
  return config.routes[proto]?[host] || config.routes["default:"]?[proto.replace(":", "")]

the404Path = config[404] && path.resolve(configDirectory, config['404']) || path.join(__dirname, "..", "404.html")
util.log "No host matched file: " + the404Path

the404 = fs.readFileSync(the404Path)

serve = (req, res, proxy, target)->
  console.log new Date, req.headers.host, req.url, "=>", target?.protocol || 404

  res.setHeader 'Server', serverAgent

  unless target?
    res.setHeader 'Content-Type', 'text/html'
    res.setHeader 'Content-Length', the404.length
    res.writeHead 404
    res.end the404

  else if target.protocol == 'file:'
    send(req, url.parse(req.url).pathname).root(target.path).pipe(res)

  else if target.protocol == 'http:'
    proxy.proxyRequest req, res,
      host: target.host
      port: target.port || 80

  else if target.protocol == 'https:'
    proxy.proxyRequest req, res,
      host: target.host
      port: target.port || 443
      target:
        https: true

  else if target.protocol == 'redirect:'
    parsed = url.parse req.url
    parsed.protocol = 'http:'
    parsed.host = target.host
    parsed.port = target.port
    target.pathname = path.join target.pathname, parsed.pathname

    res.setHeader 'Location', url.format parsed
    res.writeHead 302
    res.end "Redirecting to... " + url.format parsed

  else if target.protocol == 'redirects:'
    parsed = url.parse req.url
    parsed.protocol = 'https:'
    parsed.host = target.host
    parsed.port = target.port
    parsed.pathname = path.join target.pathname, parsed.pathname
    parsed.path =  path.join target.pathname, parsed.pathname

    res.setHeader 'Location', url.format parsed
    res.writeHead 302
    res.end "Redirecting to... " + url.format parsed

##
 # HTTP 
 ##

httpServer = httpProxy.createServer (req, res, proxy)->
  serve req, res, proxy, lookup(req, 'http:')

httpServer.on 'upgrade', (req, socket, head)->
  httpServer.proxy.proxyWebSocketRequest req, socket, head,  lookup(req, lookup(req, 'http:'))

httpServer.listen config.ports?.http || 8080, ->
  util.log "HTTP Listening on 0.0.0.0:" + (config.ports?.http || 8080)


##
 # HTTPS
 ##

if config.ssl?

  defaultSSL = path.resolve(configDirectory, config.ssl.default)
  sslPath = path.resolve(configDirectory, config.ssl.location)

  util.log "SSL enabled, default cert: " + defaultSSL
  util.log "SSL certificate store: " + sslPath

  ssl = JSON.parse fs.readFileSync defaultSSL

  httpsServer = httpProxy.createServer
    https:
      SNICallback: (hostname)->
        credentials.getCredentialsContext hostname
      key: ssl.key
      cert: ssl.cert
      ca: ssl.ca
    (req, res, proxy)->
      serve req, res, proxy, lookup(req, 'https:')

  httpsServer.on 'upgrade', (req, socket, head)->
    httpServer.proxy.proxyWebSocketRequest req, socket, head,  lookup(req, lookup(req, 'https:'))

  credentials = sslCredentials sslPath, (err)->
    if err
      util.log "Unable to read SSL credentials :( " + err.message
    else
      httpsServer.listen config.ports?.https || 8443, ->
        util.log "HTTPs Listening on 0.0.0.0:" + (config.ports?.https || 8443)

