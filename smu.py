import modconsmu
import time

import socket
host = "localhost"
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect((host, 8098))

smu = modconsmu.smu()

tick = 0.1

sock.settimeout(tick)

def log():
	t = time.time()
	data = smu.update()
	upData = "%.4f %.4f %.4f %s" % (t, data[0], -data[1]*1000, smu.driving)
	sock.send(upData)

while 1:
	try:
		s = sock.recv(1024)
		for i in s.split('\n'):
			i = i.strip()
			if not i: continue
			prop, val = i.split()
			print prop, val
			if prop == 'v':
				smu.set(volts=float(val))
			elif prop == 'i':
				smu.set(amps=float(val)/1000.0)
	except socket.timeout: pass

	log()
	


