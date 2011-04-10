#!/usr/bin/env python

# References:
# http://stackoverflow.com/questions/4372657/websocket-handshake-problem-using-python-server/5282208#5282208
# http://popdevelop.com/2010/03/a-minimal-python-websocket-server/
# http://ubuntuforums.org/showthread.php?t=715256

#
# mouse
#

from Xlib import X, display
import Xlib.ext.xtest
d = display.Display()
s = d.screen()
root = s.root

def mouse_move(x, y):
	root.warp_pointer(x, y)
	d.sync()
	
def mouse_click(btn): # 1: left, 2: middle, 3: right
	Xlib.ext.xtest.fake_input(d, Xlib.X.ButtonPress, btn)
	Xlib.ext.xtest.fake_input(d, Xlib.X.ButtonRelease, btn)
	d.sync()

#
# web
#
import SimpleHTTPServer
import SocketServer
import threading

HTTPORT = 8000

Handler = SimpleHTTPServer.SimpleHTTPRequestHandler

httpd = SocketServer.TCPServer(("", HTTPORT), Handler)

threading.Thread(target=httpd.serve_forever).start()

#
# websockets
#

import socket
import struct
import hashlib
import json

PORT = 9876

def send_message(s, lock, msg):
	lock.acquire()
	s.send("\x00%s\xff" % msg)
	lock.release()

def init_client(s, lock):
	# send screen geometry to client
	geometry = [root.get_geometry().width, root.get_geometry().height]
	print "Sending screen resolution: ", geometry
	send_message(s, lock, json.dumps(geometry))

def handle_message(addr, msg):
	print 'Message from', addr, ':', msg
	
	# mouse action
	try:
		action = json.loads(msg)
		if action[0] == 'move':
			mouse_move(int(action[1]), int(action[2]))
		elif action[0] == 'click':
			mouse_click(action[1])
	except ValueError, e:
		print "ERROR with value", msg, ":", e

def create_handshake_resp(handshake):
	final_line = ""
	lines = handshake.splitlines()
	for line in lines:
		parts = line.partition(": ")
		if parts[0] == "Sec-WebSocket-Key1":
			key1 = parts[2]
		elif parts[0] == "Sec-WebSocket-Key2":
			key2 = parts[2]
		elif parts[0] == "Host":
			host = parts[2]
		elif parts[0] == "Origin":
			origin = parts[2]
		final_line = line

	spaces1 = key1.count(" ")
	spaces2 = key2.count(" ")
	num1 = int("".join([c for c in key1 if c.isdigit()])) / spaces1
	num2 = int("".join([c for c in key2 if c.isdigit()])) / spaces2

	token = hashlib.md5(struct.pack('>II8s', num1, num2, final_line)).digest()

	return (
		"HTTP/1.1 101 WebSocket Protocol Handshake\r\n"
		"Upgrade: WebSocket\r\n"
		"Connection: Upgrade\r\n"
		"Sec-WebSocket-Origin: %s\r\n"
		"Sec-WebSocket-Location: ws://%s/\r\n"
		"\r\n"
		"%s") % (
		origin, host, token)
def handle(s, addr):
	data = s.recv(1024)
	s.send(create_handshake_resp(data))
	lock = threading.Lock()
	
	init_client(s, lock)

	while 1:
		#print "Waiting for data from", addr
		data = s.recv(1024)
		#print "Done"
		if not data:
			print "No data, closing connection"
			break
		msgs = filter(bool, data.split('\xff'))
		if not msgs:
			print "No messages, closing connection"
			break
		for msg in msgs:
			handle_message(addr, msg[1:])

	print 'Client closed:', addr
	lock.acquire()
	clients.remove(s)
	lock.release()
	s.close()

def start_server():
	print "Started mouse server at ws://%s:%s/" % (socket.gethostname(), PORT) 
	try:
		s = socket.socket()
		s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
		s.bind(('', PORT))
		s.listen(1)
		while 1:
			conn, addr = s.accept()
			print 'Connected by', addr
			clients.append(conn)
			threading.Thread(target = handle, args = (conn, addr)).start()
	except KeyboardInterrupt:
		print "^C recevied, closing socket..."
		s.close()

clients = []
start_server()
