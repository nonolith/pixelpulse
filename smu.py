#coding: UTF-8
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

sendJSON('config', settings)


def log():
	t = time.time()
	data = smu.update()
	
	sendJSON('update', {
		'time': t-tstart,
		'voltage': data[0],
		'current': data[1]*1000,
		'power': abs(data[0] * data[1]),
		'resistance': abs(data[0]/data[1]),
		'voltage(AI0)': data[2],
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
	


