#!/usr/bin/env python2
# Example driver for Pixelpulse
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>

import math, time
import pixelpulse
import webbrowser

class RCDevice(pixelpulse.Device):

	def __init__(self):
		self.v = 0
		self.i = 0
		self.q = 0
		self.r = 100.0
		self.c = 10e-3
	
		# Define the channels
		self.voltage = pixelpulse.AnalogChannel(
			name='voltage',
			unit='V',
			min=-5.0,
			max=5.0,
			state='source',
			stateOptions=['source','measure'],
			# Graph is initially shown. If False, the channel will be on the bottom bar
			showGraph=True,
			onSet=self.setChannel,
		)

		self.current = pixelpulse.AnalogChannel(
			name='current',
			unit='mA',
			min=-200,
			max=200,
			state='measure',
			stateOptions=['source','measure'],
			showGraph=True,
			onSet=self.setChannel,
		)
		
		# pixelpulse reads this property to determine which channels to show
		self.channels = [self.voltage, self.current]

		self.source = self.voltage

		self.lastTime = time.time()
		
	def start(self, server):
		""" This method is called by Pixelpulse once the server is started """
		server.poll(self.update) # ask the server to poll our update() method at its default sample rate
		
	def update(self):
		""" Polled to update the data as configured in start(). Returns a list of (channel. value) pairs """
		self.t = time.time()
		self.dt = self.t-self.lastTime
		self.lastTime = self.t
		if self.source == self.voltage:
			self.i = (self.v-self.q/self.c)/self.r
		else:
			self.v = self.q/self.c
		if (self.v>=5 and self.i>0) or (self.v<=-5 and self.i<0):
			self.i=0
		self.q += self.i*self.dt
		return [
			(self.voltage, self.v),
			(self.current, self.i*1000),
		]

	def setChannel(self, channel, value, state):
		if channel == self.voltage:
			if state == 'source' and value != None:
				self.v=value
				self.source = self.voltage
		elif channel == self.current:
			if state == 'source' and value != None:
				self.i=value/1000
		else:
			return

		if state == 'source' and self.source != channel:
			self.source = channel
		if state == 'measure':
			if self.source == self.voltage:
				self.source = self.current
			if self.source == self.current:
				self.source = self.voltage

		if self.source == self.voltage:
			self.voltage.setState('source')
			self.current.setState('measure')
		else:
			self.current.setState('source')
			self.voltage.setState('measure')
		
if __name__ == '__main__':
	dev = RCDevice()
	server = pixelpulse.DataServer(dev)
	server.start(openWebBrowser=True)
