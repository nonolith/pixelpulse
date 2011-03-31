import modconsmu
import time

import socket
host = "localhost"
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect((host, 8098))

smu = modconsmu.smu()

tick = 0.1

sock.settimeout(tick)

def log()
	t = time.time()
	data = smu.update()
	upData = "%.4f %.4f %.4f %s" % (data[0], data[1][0], -data[1][1], smu.driving)
	sock.send(upData)

while 1:
	s = sock.recv(1024)
	for i in s.split('\n')
		prop, val = i.split()
			if prop == 'v':
				smu.set(voltage=float(val))
			elif prop == 'v':
				smu.set(current=float(val))
	log()
	


