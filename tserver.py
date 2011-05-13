#coding: utf-8

from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop, PeriodicCallback
from tornado.web import Application, RequestHandler, StaticFileHandler
from tornado.websocket import WebSocketHandler

import sys, os, glob, imp, time, json

if len(sys.argv) >= 2:
	tick = float(sys.argv[1])
else:
	tick = 0.1

def findDevices(matching=None):
	devices = []
	
	drivers_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drivers")
	files = glob.glob1(drivers_dir, '*.py')
	
	if 'dummy.py' in files:
		#make dummy driver last priority
		files.remove('dummy.py')
		files.append('dummy.py')

	if 'modconsmu.py' in files:
		files.remove('modconsmu.py')
		files.insert(0, 'modconsmu.py')
	
	for fname in files:
		if fname.startswith('__'):
			continue
		name = fname.replace(".py", "")
		if matching and matching != name:
			continue
		try:
			module = imp.load_source(name, os.path.join(drivers_dir, fname))
			devices += module.getDevices()
		except Exception, e:
			print "Error loading driver %s:\n\t%s"%(name, e)
		else:
			print "Loaded driver %s"%(name)
			
	return devices


if len(sys.argv) >= 3:
	match = sys.argv[2]
else:
	match = None
devices = findDevices(matching=match)
if not len(devices):
	print "No drivers found"
	sys.exit(1)
else:
	backend = devices[0]
	print "Using device", backend



def formJSON(action, message):
	message['_action'] = action
	message = json.dumps(message)+'\n'
	return message

def log():
	if len(DataSocketHandler.clients) != 0:
		t = time.time()-startT
		packet = backend.getData(t)
		if packet:
			DataSocketHandler.sendToAll(formJSON('update', packet))

class MainHandler(RequestHandler):
	def get(self):
		self.write(open("./index.html").read())
		
class DataSocketHandler(WebSocketHandler):
	clients = []
	
	@classmethod
	def sendToAll(self, message):
		for client in self.clients:
			client.write_message(message)

	def	open(self):
		self.clients.append(self)
		self.write_message(formJSON('config', backend.getConfig()))
		
	def on_message(self, message):
		try:
			message = json.loads(message)
			action = message['_action']
			del message['_action']
			if action == 'set':
				backend.onSet(message)
		except Exception as e:
			print e
			
	def on_close(self):
		self.clients.remove(self)
		print "ws closed"

application = Application([
	(r"/dataws", DataSocketHandler),
	(r"/(.*)", StaticFileHandler, {"path": "./client/", "default_filename":"index.html"})
])

http_server = HTTPServer(application)

http_server.listen(8888)
mainLoop = IOLoop.instance()

startT = time.time()
logger = PeriodicCallback(log, tick*1000)
logger.start()

mainLoop.start()
