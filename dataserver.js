var http = require('http'),  
    io = require('socket.io')
    paperboy = require('paperboy')
    path = require('path')
    net = require('net')
    
WEBROOT = path.dirname(__filename);

server = http.createServer(function(req, res){ 
	paperboy.deliver(WEBROOT, req, res)
});
server.listen(8099);
  
var socket = io.listen(server); 

var time = 0, acc=0;


var inputserver = net.createServer(function (c) {
  c.setEncoding('utf8')
  c.write('hello\n');
  c.on('data', function(d){
  	lines = d.replace('\r', '').split('\n')
  	for (var i=0; i<lines.length; i++){
  		if (!lines[i]) continue;
  		p = lines[i].split(' ')
  		console.log(p)
  		socket.broadcast({x:parseFloat(p[0]), y:parseFloat(p[1])})
  	}
  })
});
inputserver.listen(8098);

