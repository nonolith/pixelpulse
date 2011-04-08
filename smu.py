import modconsmu
import time
import json
import socket
host = "localhost"
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect((host, 8098))

smu = modconsmu.smu()

tick = 0.1
tstart = time.time()

sock.settimeout(tick)

def sendJSON(action, msg):
	msg = msg.copy()
	msg['_action'] = action
	sock.send(json.dumps(msg)+'\n')


settings = {
	'channels': [
		{
			'name': 'time',
			'displayname': 'Time',
			'units': 's',
			'type': 'linspace',
		},
		{
			'name': 'voltage',
			'displayname': 'Voltage',
			'units': 'V',
			'type': 'device',
		},
		{
			'name': 'current',
			'displayname': 'Current',
			'units': 'mA',
			'type': 'device'
		},
		{
			'name': 'power',
			'displayname': 'Power',
			'units': 'W',
			'type': 'computed',
		}
	]
}

sendJSON('config', settings)


def log():
	t = time.time()
	data = smu.update()
	
	sendJSON('update', {
		'time': t-tstart,
		'voltage': data[0],
		'current': data[1]*1000,
		'power': data[0] * data[1],
		'_driving': 'current' if smu.driving=='i' else 'voltage'
	})

while 1:
	try:
		s = sock.recv(1024)
		for i in s.split('\n'):
			i = i.strip()
			if not i: continue
			
			msg = json.loads(i)
			print msg
			if msg['_action'] == 'set':
				for prop, val in msg.iteritems():
					if prop == 'voltage':
						smu.set(volts=val)
					elif prop == 'current':
						smu.set(amps=val/1000.0)
					else:
						print "set: bad key"
	except socket.timeout: pass
	log()
	


