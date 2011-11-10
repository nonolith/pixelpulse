#!/usr/bin/env python2
# -*- coding: utf8 -*-

import sys
import usb.core
import atexit
import pixelpulse
from optparse import OptionParser
import random, time
from cee import *

def clip(v, min, max):
	if v>max: return max
	if v<min: return min
	return v

class CEEChannel(object):
	def __init__(self, cee, index, name, show):
		self.cee = cee
		self.i=0
		self.v=0
		self.voltageGain = 1
		self.currentGain = 1
		self.driving='v'
		stateOpts = ['source', 'measure']
		self.voltageChan = pixelpulse.AnalogChannel('Voltage '+name,     'V',  0,  5,   'source',  
		                            stateOptions=stateOpts, showGraph=show, onSet=self.setVoltage)
		self.currentChan = pixelpulse.AnalogChannel('Current '+name,     'mA', -400, 400,  'measure',
		                            stateOptions=stateOpts, showGraph=show, onSet=self.setCurrent)
		self.gainChan = pixelpulse.AnalogChannel("Gain "+name, 'x', 1, 64, 'output', showGraph=False, onSet=self.setGain)
		self.channels = [self.voltageChan, self.currentChan, self.gainChan]
		self.index = index
		self.name = name

	def setDriving(self, driving):
		if self.driving != driving:
			self.updateNeeded = True
			self.driving = driving
			if self.driving == 'v':
				self.currentChan.setState('measure')
				self.voltageChan.setState('source')
			else:
				self.currentChan.setState('source')
				self.voltageChan.setState('measure')
				
			
	def setVoltage(self, chan, volts, state=None):
		if state is not None:
			self.setDriving('v' if state=='source' else 'i')
		if volts is not None:
			self.v = clip(volts, 0, 5)
			self.cee.set(self.index, v=self.v)
				
	def setCurrent(self, chan, ma, state=None):
		if state is not None:
			self.setDriving('i' if state=='source' else 'v')
		if ma is not None:
			self.i = clip(ma, -400, 400)
			self.cee.set(self.index, i=self.i/1000.0)

	def getChanData(self, replypkt):
		return [(self.voltageChan, replypkt[self.name.lower()+'_v']),
				(self.currentChan, replypkt[self.name.lower()+'_i']*1000),
				(self.gainChan, self.getGain(self.name.lower()))]

	def getGain(self, name):
		if self.name.lower() == 'a':
			return self.cee.gains[1]
		elif self.name.lower() == 'b':
			return self.cee.gains[2]

	def setGain(self, chan, gain, state=None):
		if self.name.lower() == 'a':
			chan = 1 
		elif self.name.lower() == 'b':
			chan = 2
		print (chan, gain)
		self.cee.set(0, x=(chan, gain))


class CEE_vendor_req(pixelpulse.Device):
	def __init__(self):
		stateOpts = ['source', 'measure']

		self.cee = CEE()
		
		self.chanA = CEEChannel(self.cee, 0, 'A', True)
		self.chanB = CEEChannel(self.cee, 1, 'B', True)
		self.ceechannels = [self.chanA, self.chanB]
			
		self.channels = sum([x.channels for x in self.ceechannels], [])
		
		self.dev = usb.core.find(idVendor=0x9999, idProduct=0xFFFF)
		if self.dev is None:
			raise IOError("CEE not found")
	def start(self, server):
		server.poll(self.poll)
		
	def poll(self):
		data = self.cee.readADC()
		return sum([x.getChanData(data) for x in self.ceechannels], [])

if __name__ == '__main__':
	dev = CEE_vendor_req()
	server = pixelpulse.DataServer(dev)
	server.start(openWebBrowser=False)
