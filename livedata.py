#coding: utf-8

from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop, PeriodicCallback
from tornado.web import Application, RequestHandler, StaticFileHandler
from tornado.websocket import WebSocketHandler

import sys, os, glob, imp, time, json

class Channel(object):
	json_properties = ['name', 'id', 'state', 'showGraph', 'settable']
	
	def __init__(self, name, state='input', showGraph=False, onSet=None):
		self.name = name
		self.id = name.lower()
		self.state = state
		self.showGraph = showGraph
		self.onSet = onSet
		self.settable = bool(onSet)
		
	def getConfig(self):
		config = {}
		o = self
		while hasattr(o, 'json_properties'):
			for prop in o.json_properties:
				config[prop] = getattr(self, prop)
			o = super(type(o), o)
		return config
		
	def onSet(self, v):
		print "Can't set channel %s"%self.name
		
	def setState(self, state):
		self.state = state
		self._stateChanged(self)
		

class AnalogChannel(Channel):
	json_properties = ['unit', 'min', 'max']

	def __init__(self, name, unit, min, max, state='input', **kw):
		super(AnalogChannel, self).__init__(name, state, **kw)
		self.unit = unit
		self.min = min
		self.max = max

class Device(object):
	def start(self):
		pass
	
	def stop(self):
		pass

class DataSocketHandler(WebSocketHandler):
	def __init__(self, *args, **kwds):
		super(DataSocketHandler, self).__init__(*args)
		self.server = kwds['server_instance']

	def	open(self):
		self.server.onConnect(self)
		
	def on_message(self, message):
		try:
			message = json.loads(message)
			action = message['_action']
			del message['_action']
			if action == 'set':
				self.server.onSet(message)
		except Exception as e:
			print e
			
	def on_close(self):
		self.server.onDisconnect(self)

class DataServer(object):
	def __init__(self, devices, port=8888, poll_tick=0.1):
		if not isinstance(devices, list): devices =  [devices]
		self.devices = devices 
		self.clients = []
		self.channels = {}
		self.poll_tick = poll_tick
		self.poll_fns = []
		for dev in devices:
			for channel in dev.channels:
				channel._stateChanged = self.onStateChange
				self.channels[channel.id] = channel
			
		if not 'time' in self.channels:
			self.channels['time'] = AnalogChannel('Time','s',-30,'auto',state='live')
		
		self.application = Application([
			(r"/dataws", DataSocketHandler, {'server_instance':self}),
			(r"/(.*)", StaticFileHandler, {"path": "./client/", "default_filename":"index.html"})
		])
		
		self.http_server = HTTPServer(self.application)
		self.http_server.listen(port)
		self.mainLoop = IOLoop.instance()

	def formJSON(self, action, message):
		message['_action'] = action
		message = json.dumps(message)+'\n'
		return message

	def data(self, data):
		if len(self.clients) != 0:
			packet = {}
			for channel, value in data:
				packet[channel.id] = value
			
			if not packet.has_key('time'):
				packet['time'] = time.time() - self.startT	
			
			if packet:
				self.sendToAll(self.formJSON('update', packet))
				
	def sendToAll(self, message):
		for client in self.clients:
			client.write_message(message)
			
	def getConfigMessage(self):
		s = []
		for name, channel in self.channels.iteritems():
			s.append(channel.getConfig())
		return {'channels': s}
		
	def onConnect(self, client):
		self.clients.append(client)
		client.write_message(self.formJSON('config', self.getConfigMessage()))
		
	def onDisconnect(self, client):
		self.clients.remove(client)
		
	def onSet(self, message):
		for k, v in message.iteritems():
			self.channels[k].onSet(v)
			
	def onStateChange(self, channel):
		self.sendToAll(self.formJSON('update', {'channel':channel.id,'state':channel.state}))
			
	def start(self):
		self.startT = time.time()
		
		for dev in self.devices:
			dev.start(self)
		
		if self.poll_fns:
			self.poller = PeriodicCallback(self.onPoll, self.poll_tick*1000)
			self.poller.start()
		
		self.mainLoop.start()
		
	def poll(self, callback):
		self.poll_fns.append(callback)
	
	def onPoll(self):
		for f in self.poll_fns: self.data(f())

if __name__ == "__main__":
	AnalogChannel('test', 'Test', 'A', 0, 10).getConfig()
	s = DataServer()
	s.start()
	
	#print "Run virtualrc.py for a demo"
