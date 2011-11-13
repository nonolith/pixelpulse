#coding: utf-8

# Pixelpulse - framework to visualize and control signals in a browser-based interface
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>
# (C) 2011 Ian Daniher  (Nonolith Labs) <ian@nonolithlabs.com>

from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop, PeriodicCallback
from tornado.web import Application, RequestHandler, StaticFileHandler
from tornado.websocket import WebSocketHandler

import sys, os, glob, imp, time, json, webbrowser

class Device(object):
	"""Base class for device drivers
	
	Your `__init__` method must set the property `channels` to a list of 
	pixelpulse.Channel subclasses for the channels supported by your device.
	"""
	
	def start(self, server):
		"""Called when the server is ready to receive data
		
		server -- A pixelpulse.DataServer instance
		"""
		pass
	
	def stop(self):
		"""Called when the server wants to stop receiving data"""
		pass

class DataServer(object):
	""" Pixelpulse server """
	
	def __init__(self, devices, port=8888, poll_tick=0.07):
		"""Arguments:
		devices -- list of pixelpulse.Device subclasses for the devices you wish to monitor
		port -- the port to listen for HTTP and WebSocket connections (default 8888)
		poll_tick -- the tick (in seconds) at which devices are polled for new data (default 0.07)
		"""
		
		if not isinstance(devices, list): devices =  [devices]
		self.port = port
		self.devices = devices 
		self.clients = []
		self.channels = {}
		self.channel_list = []
		self.poll_tick = poll_tick
		self.poll_fns = []
		self.started = False
		for dev in devices:
			self.channel_list.extend(dev.channels)
			for channel in dev.channels:
				channel._stateChanged = self._onStateChange
				self.channels[channel.id] = channel
			
		if not 'time' in self.channels:
			ch = AnalogChannel('Time','s',-30,'auto',state='live')
			self.channels['time'] = ch
			self.channel_list.insert(0, ch)
		
		self.application = Application([
			(r"/dataws", self._DataSocketHandler, {'server_instance':self}),
			(r"/(.*)", StaticFileHandler, {"path": "./client/", "default_filename":"index.html"})
		])
		
		self.http_server = HTTPServer(self.application)
		self.http_server.listen(port, '127.0.0.1')
		self.mainLoop = IOLoop.instance()

	def _formJSON(self, action, message):
		message['_action'] = action
		message = json.dumps(message)+'\n'
		return message

	def updateConfig(self):
		self._sendToAll(self._formJSON('config', self.getConfigMessage()))

	def data(self, data):
		"""Send a new datapoint to connected clients.
		
		Arguments:
		data -- list of (pixelpulse.Channel instance, float value) pairs
		
		If a channel called "time" exists, it will be used as the time axis.
		If not, a time axis will be created automatically.
		"""
		
		if len(self.clients) != 0:
			packet = {}
			for channel, value in data:
				packet[channel.id] = value
			
			if not packet.has_key('time'):
				packet['time'] = time.time() - self.startT	
			
			if packet:
				self._sendToAll(self._formJSON('update', packet))
				
	def _sendToAll(self, message):
		"""Send a message to all websocket clients"""
		for client in self.clients:
			client.write_message(message)
			
	def getConfigMessage(self):
		"""Generate a configuration message containing information about all channels"""
		s = []
		for channel in self.channel_list:
			s.append(channel._getConfig())
		return {'channels': s}
		
	class _DataSocketHandler(WebSocketHandler):
		"""Internal Tornado handler for new WebSocket connections"""
		def __init__(self, *args, **kwds):
			super(type(self), self).__init__(*args)
			self.server = kwds['server_instance']

		def	open(self):
			self.server._onConnect(self)
		
		def on_message(self, message):
			try:
				message = json.loads(message)
				action = message['_action']
				del message['_action']
				if action == 'set':
					self.server._onSet(message)
			except Exception as e:
				print e
			
		def on_close(self):
			self.server._onDisconnect(self)

	def _onConnect(self, client):
		self.clients.append(client)
		client.write_message(self._formJSON('config', self.getConfigMessage()))
		
	def _onDisconnect(self, client):
		self.clients.remove(client)
		
		if self.openWebBrowser and len(self.clients)==0:
			self.quit()
	
	def _onSet(self, message):
		chan = self.channels[message['channel']]
		chan.onSet(chan, message['value'], message['state'])
			
	def _onStateChange(self, channel):
		self._sendToAll(self._formJSON('state', {'channel':channel.id,'state':channel.state}))
			
	def start(self, openWebBrowser=False):
		"""Start the server and all associated devices. Gives control to the
		Tornado IO loop and does not return until the server terminates"""

		self.startT = time.time()
		self.openWebBrowser = openWebBrowser
		
		if openWebBrowser:
			webbrowser.open("http://127.0.0.1:%i"%self.port)

		for dev in self.devices:
			dev.start(self)
		
		self._start_poller()
		
		self.started = True
		print "Server running at http://127.0.0.1:%i"%self.port
		self.mainLoop.start()
		
	def _start_poller(self):
		"""Begin polling the callbacks configured with poll()"""
		if self.poll_fns:
			self.poller = PeriodicCallback(self._onPoll, self.poll_tick*1000)
			self.poller.start()
		
	def poll(self, callback):
		"""Arrange for callback to be called at the default poll interval.
		Used by drivers that need to poll a device or otherwise take a regular
		action"""
		
		self.poll_fns.append(callback)
		if self.started and not hasattr(self, 'poller'):
			self._start_poller()
	
	def _onPoll(self):
		for f in self.poll_fns:
			r = f()
			if r:
				self.data(r)
				
	def quit(self, *ignore):
		"""Make the Tornado IO loop exit"""
		self.mainLoop.stop()

class Channel(object):
	"""Base class for pixelpulse channels"""
	
	json_properties = ['name', 'id', 'type', 'state', 'stateOptions', 'color', 'showGraph', 'settable']
	
	def __init__(self, name, state='input', stateOptions=None, color='blue', showGraph=False, onSet=None):
		"""Arguments:
		name -- the channel name
		state -- the initial channel state (default 'input')
		stateOptions -- list of possible states for the channel
		color -- HTML color for the channel's line in the UI (default 'blue')
		showGraph -- if True, show the graph initially, if False, the channel goes in the bottom bar
		onSet -- callback for when the channel is set from the UI. Takes arguments (channel, value, state)
		"""
		
		self.name = name
		self.id = name.lower()
		self.state = state
		if not stateOptions:
			self.stateOptions = [state]
		else:
			self.stateOptions = stateOptions
		self.color = color
		self.showGraph = showGraph
		self.onSet = onSet
		self.settable = bool(onSet)
		
	def _getConfig(self):
		config = {}
		o = self
		while hasattr(o, 'json_properties'):
			for prop in o.json_properties:
				config[prop] = getattr(self, prop)
			o = super(type(o), o)
		return config
		
	def onSet(self, channel, value, state):
		""" Default onSet callback. Just prints an error. 
		You can pass an onSet keyword parameter with a callback to the constructor
		to override this and handle value and state changes """
		
		print "Can't set channel %s"%self.name
		
	def setState(self, state):
		"""Update the state of a channel. Note that when you receive a new
		state through your onSet callback, you must setState() it to "accept"
		the new state and update the UI"""
		self.state = state
		self._stateChanged(self)
		

class AnalogChannel(Channel):
	"""Analog channel"""
	json_properties = ['unit', 'min', 'max']
	type = 'analog'

	def __init__(self, name, unit, min, max, state='input', **kw):
		"""Arguments:
		name -- the channel name
		unit -- unit to be displayed next to the channel
		min -- minimum allowed value
		max -- maximum allowed value
		state -- the initial channel state (default 'input')
		
		Keyword arguments: see pixelpulse.Channel
		"""
		super(AnalogChannel, self).__init__(name, state, **kw)
		self.unit = unit
		self.min = min
		self.max = max
		
class DigitalChannel(Channel):
	""" Digital (binary, boolean) channel """
	json_properties = []
	type = 'digital'
	
	def __init__(self, name, state='input', **kw):
		"""Arguments:
		name -- the channel name
		state -- the initial channel state (default 'input')
		
		Keyword arguments: see pixelpulse.Channel
		"""
		super(DigitalChannel, self).__init__(name, state, **kw)

if __name__ == "__main__":
	print "Run sine.py for a demo"
