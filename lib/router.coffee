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

serverAgent = config.get('serverAgent') || pkg.name + "/" + pkg.version
util.log "Server identifier: " + serverAgent

the404Path = config[404] && path.resolve(configDirectory, config['404']) || path.join(__dirname, "..", "404.html")
util.log "No host matched file: " + the404Path

the404 = fs.readFileSync(the404Path)

serve = (req, res, proxy, conf)->
  console.log new Date, req.headers.host, req.url, "=>", conf?.target?.protocol || 404

  res.setHeader 'Server', serverAgent

  if conf?
    rewrittenUrl = conf.rewrite req.url
    req.url = rewrittenUrl

  unless conf?
    res.setHeader 'Content-Type', 'text/html'
    res.setHeader 'Content-Length', the404.length
    res.writeHead 404
    res.end the404

  else if conf.target.protocol == 'file:'
    parsed = url.parse req.url
    send(req, parsed.pathname, { root: conf.target.path }).pipe(res)

  else if conf.target.protocol == 'http:'
    proxy.proxyRequest req, res,
      host: conf.target.hostname
      port: conf.target.port || 80

  else if conf.target.protocol == 'https:'
    proxy.proxyRequest req, res,
      host: conf.target.hostname
      port: conf.target.port || 443
      target:
        https: true

  else if conf.target.protocol == 'redirect:'
    parsed = url.parse req.url
    parsed.protocol = 'http:'
    host = [conf.target.hostname]
    host.push(conf.target.port) if conf.target.port?
    parsed.host = host.join(":")
    
    res.setHeader 'Location', url.format parsed
    res.writeHead 302
    res.end "Redirecting to... " + url.format parsed

  else if conf.target.protocol == 'redirects:'
    parsed = url.parse req.url
    parsed.protocol = 'https:'
    host = [conf.target.hostname]
    host.push(conf.target.port) if conf.target.port?
    parsed.host = host.join(":")

    res.setHeader 'Location', url.format parsed
    res.writeHead 302
    res.end "Redirecting to... " + url.format parsed

  else
    res.writeHead 500
    util.log "Server misconfigured, unknown protocol: " + conf.target.protocol
    res.end "Internal server error"

##
 # HTTP 
 ##

httpServer = httpProxy.createServer (req, res, proxy)->
  serve req, res, proxy, config.lookup(req, 'http:', req.url)

httpServer.on 'upgrade', (req, socket, head)->
  httpServer.proxy.proxyWebSocketRequest req, socket, head, config.lookup(req, 'http:')

httpServer.listen config.get('ports')?.http || 8080, ->
  util.log "HTTP Listening on 0.0.0.0:" + (config.get('ports')?.http || 8080)


##
 # HTTPS
 ##

if config.get('ssl')?

  defaultSSL = path.resolve(configDirectory, config.get('ssl').default)
  sslPath = path.resolve(configDirectory, config.get('ssl').location)

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
      serve req, res, proxy, config.lookup(req, 'https:')

  httpsServer.on 'upgrade', (req, socket, head)->
    httpsServer.proxy.proxyWebSocketRequest req, socket, head,  lookup(req, config.lookup(req, 'https:'))

  credentials = sslCredentials sslPath, (err)->
    if err
      util.log "Unable to read SSL credentials :( " + err.message
    else
      httpsServer.listen config.get('ports')?.https || 8443, ->
        util.log "HTTPs Listening on 0.0.0.0:" + (config.get('ports')?.https || 8443)

