http = require('http')
fs = require('fs')

server = http.createServer (req, res) ->
	req.setEncoding('utf8')
	body = ''
	req.addListener "data", (chunk) ->
		body += chunk
	
	req.addListener "end", ->
		json = JSON.parse(body)
		
		if not /^[A-Za-z0-9]+$/.test(json.serial)
			console.erro('invalid serial')
			return
		
		fname = "calibration/#{json.serial}_#{+new Date()}.json"
		
		fs.writeFile fname, body, ->
			console.log("Saved #{fname}")
			res.writeHead(200, {'Content-Type': 'text/plain', 'Access-Control-Allow-Origin':'http://localhost:8000'})
			res.end('OK')

server.listen(1337, "127.0.0.1")
console.log('Server running at http://127.0.0.1:1337/')
