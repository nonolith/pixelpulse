#coding: utf-8

from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop, PeriodicCallback
from tornado.web import Application, RequestHandler, StaticFileHandler
from tornado.websocket import WebSocketHandler

import os
import modconsmu
import time
import json

clients = []
smu = modconsmu.smu()

tick = .05

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


def sendToAll(clients, message):
	for client in clients:
		client.write_message(message)

def formJSON(action, message):
	message['_action'] = action
	message = json.dumps(message)+'\n'
	return message

def formMessage(smu):
	data = smu.update()
	return {
		'time': time.time()-startT,
		'voltage': data[0],
		'current': data[1]*1000,
		'power': abs(data[0] * data[1]),
		'resistance': abs(data[0]/data[1]),
		'voltage(AI0)': data[2],
		'_driving': 'current' if smu.driving=='i' else 'voltage'}

def log():
	if len(clients) != 0:
		sendToAll(clients, formJSON('update', formMessage(smu)))
	time.sleep(tick)

class MainHandler(RequestHandler):
	def get(self):
		self.write(open("./index.html").read())

class DataSocketHandler(WebSocketHandler):
	def	open(self):
		clients.append(self)
		self.write_message(formJSON('config', settings))
	def on_message(self, message):
		try:
			message = json.loads(message)
			if message['_action'] == 'set':
				for prop, val in message.iteritems():
					if prop == 'voltage':
						smu.set(volts=val)
					elif prop == 'current':
						smu.set(amps=val/1000.0)
					elif prop == '_action' and val == 'set':
						pass
					else:
						print prop, val + "is invalid"
		except Exception as e:
			print e
	def on_close(self):
		clients.remove(self)
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
