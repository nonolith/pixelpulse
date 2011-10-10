#!/usr/bin/env python2
# -*- coding: utf8 -*-

import sys
import usb.core
import atexit
import pixelpulse
from optparse import OptionParser
import random, time

MODE_DISABLED=0
MODE_SVMI=1
MODE_SIMV=2

def unpackSign(n):
	return n - (1<<12) if n>2048 else n

class CEE(object):
	def __init__(self):
		self.init()

	def init(self):
		self.dev = usb.core.find(idVendor=0x9999, idProduct=0xffff)
		if not self.dev:
			raise IOError("device not found")
			
		self.dev.set_configuration()

	def b12unpack(self, s):
		"Turn a 3-byte string containing 2 12-bit values into two ints"
		return s[0]|((s[1]&0x0f)<<8), ((s[1]&0xf0) >> 4)|(s[2]<<4)
		
	def readADC(self):
		data = self.dev.ctrl_transfer(0x40|0x80, 0xA0, 0, 0, 6)
		l = self.b12unpack(data[0:3]) + self.b12unpack(data[3:6])
		print l
		vals = map(unpackSign, l)
		return {
			'a_v': vals[0]/2048.0*2.5,
			'a_i': ((vals[1]/2048.0*2.5))/45/.07,
			'b_v': vals[2]/2048.0*2.5,
			'b_i': ((vals[3]/2048.0*2.5))/45/.07,
		}

	def set(self, chan, v=None, i=None):
		cmd = 0xAA+chan
		if v is not None:
			dacval = int(round(v/5.0*4095))
			print dacval
			self.dev.ctrl_transfer(0x40|0x80, cmd, dacval, MODE_SVMI, 6)
		elif i is not None:
			dacval = int((2**12*(1.25+(45*.07*i)))/2.5)
			print dacval
			self.dev.ctrl_transfer(0x40|0x80, cmd, dacval, MODE_SIMV, 6)
		else:
			self.dev.ctrl_transfer(0x40|0x80, cmd, 0, MODE_DISABLED, 6)	

	def setA(self, v=None, i=None):
		self.set(0, v, i)
	
	def setB(self, v=None, i=None):
		self.set(1, v, i)


def clip(v, min, max):
	if v>max: return max
	if v<min: return min
	return v

class CEEChannel(object):
	def __init__(self, cee, index, name, show):
		self.cee = cee
		self.i=0
		self.v=0
		self.driving='v'
		stateOpts = ['source', 'measure']
		self.voltageChan = pixelpulse.AnalogChannel('Voltage '+name,     'V',  0,  2.5,   'source',  
		                            stateOptions=stateOpts, showGraph=show, onSet=self.setVoltage)
		self.currentChan = pixelpulse.AnalogChannel('Current '+name,     'mA', -400, 400,  'measure',
		                            stateOptions=stateOpts, showGraph=show, onSet=self.setCurrent)

		self.channels = [self.voltageChan, self.currentChan]
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
			self.v = clip(volts, 0, 2.5)
			self.cee.set(self.index, v=self.v)
				
	def setCurrent(self, chan, ma, state=None):
		if state is not None:
			self.setDriving('i' if state=='source' else 'v')
		if ma is not None:
			self.i = clip(ma, -400, 400)
			self.cee.set(self.index, i=self.i/1000.0)

	def getChanData(self, replypkt):
		return [(self.voltageChan, replypkt[self.name.lower()+'_v']),
				(self.currentChan, replypkt[self.name.lower()+'_i']*1000)]
		

class CEE_vendor_req(pixelpulse.Device):
	def __init__(self):
		stateOpts = ['source', 'measure']

		self.cee = CEE()

		self.chanA = CEEChannel(self.cee, 0, 'A', False)
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
		#print data
		return sum([x.getChanData(data) for x in self.ceechannels], [])

if __name__ == '__main__':
	dev = CEE_vendor_req()
	server = pixelpulse.DataServer(dev)
	server.start(openWebBrowser=True)
