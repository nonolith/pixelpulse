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
	upData = "%.4f %.4f %.4f %s" % (t, data[0], data[1]*1000, smu.driving)
	sock.send(upData)

while 1:
	try:
		s = sock.recv(1024)
		for i in s.split('\n'):
			i = i.strip()
			if not i: continue
			try:
				prop, val = i.split()
			except Exception as inst:
				print "exception:", inst
				print "bad key/value pair:", prop, val
				prop = 'NONE'
				val = 0
			if prop == 'v':
				try:
					val = float(val)
				except Exception as inst:
					print "exception:", inst
					print "bad value:", val
				smu.set(volts=val)
			elif prop == 'i':
				try:
					val = float(val)/1000.0
				except Exception as inst:
					print "exception:", inst
					print "bad value:", val
				smu.set(amps=val)
			else:
				print "bad key"
	except socket.timeout: pass
	log()
	


