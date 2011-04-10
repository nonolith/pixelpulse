#coding: utf-8

# References:
# http://stackoverflow.com/questions/4372657/websocket-handshake-problem-using-python-server/5282208#5282208
# http://popdevelop.com/2010/03/a-minimal-python-websocket-server/
# http://ubuntuforums.org/showthread.php?t=715256

tick = .1

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
# smu
#
import modconsmu
import time

tstart = time.time()

smu = modconsmu.smu()

settings = {
	'channels': [
		{
			'name': 'time',
			'displayname': 'Time',
			'units': 's',
			'type': 'linspace',
			'axisMin': -30,
			'axisMax': 'auto',
		},
		{
			'name': 'voltage',
			'displayname': 'Voltage',
			'units': 'V',
			'type': 'device',
			'axisMin': -10,
			'axisMax': 10,
		},
		{
			'name': 'current',
			'displayname': 'Current',
			'units': 'mA',
			'type': 'device',
			'axisMin': -200,
			'axisMax': 200,
		},
		{
			'name': 'resistance',
			'displayname': 'Resistance',
			'units': u'Ω',
			'type': 'computed',
			'axisMin': 0,
			'axisMax': 1000,
		},
		{
			'name': 'power',
			'displayname': 'Power',
			'units': 'W',
			'type': 'computed',
			'axisMin': 0,
			'axisMax': 2,
		},
		{
			'name': 'voltage(AI0)',
			'displayname': 'Voltage(AI0)',
			'units': 'V',
			'type': 'computed',
			'axisMin': 0,
			'axisMax': 4.096,
		}
	]
}


def log(s, lock):
	t = time.time()
	data = smu.update()
	sendJSON(s, lock, 'update', {
		'time': t-tstart,
		'voltage': data[0],
		'current': data[1]*1000,
		'power': abs(data[0] * data[1]),
		'resistance': abs(data[0]/data[1]),
		'voltage(AI0)': data[2],
		'_driving': 'current' if smu.driving=='i' else 'voltage'
	})


#
# websockets
#

import socket
import struct
import hashlib
import json

PORT = 9876

def sendJSON(s, lock, action, msg):
	msg = msg.copy()
	msg['_action'] = action
	msg = json.dumps(msg)+'\n'
	lock.acquire()
	s.send("\x00%s\xff" % msg)
	lock.release()

def handle_message(s, lock, addr, msg):
	print 'Message from', addr, ':', msg
	try:
		msg = json.loads(msg)
		if msg['_action'] == 'set':
			for prop, val in msg.iteritems():
				if prop == 'voltage':
					smu.set(volts=val)
				elif prop == 'current':
					smu.set(amps=val/1000.0)
				else:
					print "set: bad key"
	except socket.timeout: pass

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

def handle(conn, lock, addr):
	data = conn.recv(1024)
	conn.send(create_handshake_resp(data))
	sendJSON(conn, lock, 'config', settings)
	while 1:
		try:
			data = conn.recv(1024)
			if not data:
				print "No data, closing connection"
				break
			msgs = filter(bool, data.split('\xff'))
			if not msgs:
				print "No messages, closing connection"
				break
			for msg in msgs:
				handle_message(conn, lock, addr, msg[1:])
		except socket.timeout: pass
		log(conn, lock)
	print 'Client closed:', addr
	lock.acquire()
	clients.remove(conn)
	lock.release()
	conn.close()

def pushData(lock, foo):
	while True:
		for client in clients:
			log(client, lock)
		time.sleep(tick)

def start_server():
	print "Started server at ws://%s:%s/" % (socket.gethostname(), PORT) 
	try:
		s = socket.socket()
		s.settimeout(tick)
		s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
		s.bind(('', PORT))
		lock = threading.Lock()
		s.listen(1)
		threading.Thread(target = pushData, args = (lock, 'junk')).start()
		while 1:
			try:
				conn, addr = s.accept()
				print 'Connected by', addr
				clients.append(conn)
				threading.Thread(target = handle, args = (conn, lock, addr)).start()
			except socket.timeout: pass  
	except KeyboardInterrupt:
		print "^C recevied, closing socket..."
		s.close()

clients = []

#lock = threading.Lock()
#settings['channels'][3]['axisMax'] = 100
#sendJSON(clients[0], lock, 'config', settings)


threading.Thread(target = start_server).start()
