import modconsmu
import time
import json
import socket
host = "localhost"
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect((host, 8098))

smu = modconsmu.smu()

tick = 0.1

sock.settimeout(tick)

def sendJSON(action, msg):
	msg = msg.copy()
	msg['_action'] = action
	sock.send(JSON.dumps(msg)+'\n')

sensors = {
	'time': {
		'displayname': 'Time',
		'units': 's',
		'type': 'linspace',
	}
	'voltage': {
		'displayname': 'Voltage',
		'units': 'V',
		'type': 'device',
	},
	'current': {
		'displayname': 'Current',
		'units': 'mA',
		'type': 'device'
	}
	'power',
		'displayname': 'Power',
		'units': 'W',
		'type': 'computed',
	}
}

sendJSON('configChannels', sensors)


def log():
	t = time.time()
	data = smu.update()
	
	sendJSON('update' {
		'time': t,
		'voltage': data[0],
		'current': data[1]*1000,
		'_driving': 'current' if smu.driving=='i' else 'voltage'
	})

while 1:
	try:
		s = sock.recv(1024)
		for i in s.split('\n'):
			i = i.strip()
			if not i: continue
			
			msg = json.loads(i)
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
	


