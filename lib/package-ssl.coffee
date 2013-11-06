argv = require('optimist').argv
fs   = require('fs')

struct = {}

unless argv.key and argv.cert
  console.error "--key and --cert MUST be specified"
  process.exit()

struct.key = fs.readFileSync(argv.key).toString()
struct.cert = fs.readFileSync(argv.cert).toString()

if argv.ca
  unless Array.isArray(argv.ca) 
    argv.ca = [argv.ca]
  struct.ca = argv.ca.map (ca)->
    fs.readFileSync(ca).toString()


if argv.out
  console.log "Writing SSL JSON to", argv.out
  fs.writeFileSync argv.out, JSON.stringify(struct, null, 2)
else
  console.log JSON.stringify struct, null, 2