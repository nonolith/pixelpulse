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

var inputserver = net.createServer(function (c) {
  c.setEncoding('utf8')
  c.write('hello\n');
  c.on('data', function(d){
  	lines = d.replace('\r', '').split('\n')
  	for (var i=0; i<lines.length; i++){
  		if (!lines[i]) continue;
  		if (lines[i][0] == '#'){
  			socket.broadcast({log:lines[i].slice(1)})
  		}else{
  			p = lines[i].split(' ')
  			socket.broadcast({x:parseFloat(p[0]), v:parseFloat(p[1]), i:parseFloat(p[2])})
  		}
  	}
  })
});
inputserver.listen(8098);

