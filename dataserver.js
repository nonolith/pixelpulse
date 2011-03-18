var http = require('http'),  
    io = require('socket.io')
    paperboy = require('paperboy')
    path = require('path')
    
WEBROOT = path.dirname(__filename);

server = http.createServer(function(req, res){ 
	paperboy.deliver(WEBROOT, req, res)
});
server.listen(8099);
  
var socket = io.listen(server); 

var time = 0, acc=0;

setInterval(function(){
	acc = acc*0.8 + Math.random()*0.2
	socket.broadcast({x:time, y:acc})
	time += 0.05
}, 50)
