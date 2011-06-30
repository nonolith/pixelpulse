#!/usr/bin/env python2
# -*- coding: utf8 -*-
# Olin ModCon SMU driver for Pixelpulse
# Distributed under the terms of the BSD License
# (C) 2011 Ian Daniher  (Nonolith Labs) <ian@nonolithlabs.com>

import sys
import usb.core
import atexit
import pixelpulse
from optparse import OptionParser
import random, time

class ModconSMU(pixelpulse.Device):
	vReqs = {'UPDATE' : 1, 
	        'SET_DIGOUT' : 2, 
	        'GET_DAC_VALS' : 3,
	        'SET_DAC_VALS' : 4,
	        'GET_VADC_VALS' : 5,
	        'GET_IADC_VALS' : 7,
	        'GET_RES_VAL' : 9,
	        'GET_NAME' : 11,
	        'SET_NAME' : 12}
	
	def __init__(self, vlimit):
		stateOpts = ['source', 'measure']
		self.voltageChan =    pixelpulse.AnalogChannel('Voltage',     'V',  vlimit[0],  vlimit[1],   'source',  
		                            stateOptions=stateOpts, showGraph=True, onSet=self.setVoltage)
		self.currentChan =    pixelpulse.AnalogChannel('Current',     'mA', -200, 200,  'measure',
		                            stateOptions=stateOpts, showGraph=True, onSet=self.setCurrent)
		self.resistanceChan = pixelpulse.AnalogChannel('Resistance',  u'Ω', 0,    2000, 'computed')
		self.powerChan =      pixelpulse.AnalogChannel('Power',        'W', 0,    2,    'computed')
		#self.aiChan =         pixelpulse.AnalogChannel('Voltage(AI0)', 'V', 0,    4.096, 'input')
		self.channels = [self.voltageChan, self.currentChan, self.resistanceChan,
		                 self.powerChan]
		                 
		self.ifilt = 0
	
	
		"""Find a USB device with the VID and PID of the ModCon SMU."""
		self.zeroV = 0x07CF 
		self.zeroI = 0x07CF
		self.maxV = 9.93
		self.minV = -10.45
		self.scaleFactorV = (self.maxV-self.minV)/(2**12)
		self.v = 0
		self.i = 0
		self.driving = "i"
		self.updateNeeded = 0
		#find device
		self.dev = usb.core.find(idVendor=0x6666, idProduct=0x0005)
		if self.dev is None:
			raise IOError("SMU not found")
		#determine callibration values
		VADC_VALS = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['GET_VADC_VALS'], wValue = 0, wIndex = 0, data_or_wLength = 4)
		IADC_VALS = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['GET_IADC_VALS'], wValue = 0, wIndex = 0, data_or_wLength = 4)
		RES_VAL = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['GET_RES_VAL'], wValue = 0, wIndex = 0, data_or_wLength = 2)
		DAC_VALS = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['GET_DAC_VALS'], wValue = 0, wIndex = 0, data_or_wLength = 4)
		self.DAC = ( DAC_VALS[0] | ( DAC_VALS[1] << 8 ) ) / 16.0
		VALUE = self.sign( DAC_VALS[2] | DAC_VALS[3] << 8 )
		self.DACGAIN = -200*VALUE/16384.0
		self.VADC = ( VADC_VALS[0] | ( VADC_VALS[1] << 8 ) ) / 16.0
		VALUE = self.sign( VADC_VALS[2] | ( VADC_VALS[3] << 8 ) )
		self.VADCGAIN = 50*VALUE/16384.0
		self.IADC = ( IADC_VALS[0] | ( IADC_VALS[1] << 8 ) ) / 16.0
		VALUE = self.sign( IADC_VALS[2] | ( IADC_VALS[3] << 8 ) )
		self.IADCGAIN = 50*VALUE/16384.0
		VALUE = self.sign( RES_VAL[0] | ( RES_VAL[1] << 8 ) )
		self.RES = 51*VALUE/16384.0
		#add safety feature
		atexit.register(self.stop)

	def sign(self, x):
		"""Undo two's complement signing."""
		if x > 32767:
			return 65536-x
		else:
			return x

	def update(self, mod = 1):
		"""updates smu target V/I, returns actual V/I"""
		if self.driving == 'v':
			value = int(round(self.zeroV - (self.v+0.04)/self.scaleFactorV))
			if cmp(value, 0) == -1:
				value = int(round((self.v+0.04)/self.scaleFactorV - self.zeroV))
			direction = 0
		elif self.driving == 'i':
			value = int(round(self.zeroI + self.i * 10000))
			direction = 1
		else:
			print("bad type")
		if self.updateNeeded == 1:
			self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['UPDATE'], wValue = self.zeroV, wIndex = 0, data_or_wLength = 12)
			self.dev.ctrl_transfer(bmRequestType = 0x40, bRequest = self.vReqs['SET_DIGOUT'], wValue = direction, wIndex = 0, data_or_wLength = [0]*12)
			self.updateNeeded = 0
		data = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['UPDATE'], wValue = value, wIndex = 0, data_or_wLength = 12)
		retVolt = ((data[0]|data[1]<<8)-self.VADC)/self.VADCGAIN + 0.053
		retAmp = ((data[4]|data[5]<<8)-self.IADC)/(self.IADCGAIN*self.RES) - 0.000263 
		modVolt = (data[6]|data[7]<<8)*(4.096/1023)
		if mod:
			return (retVolt, retAmp, modVolt)
		else:
			return (retVolt, retAmp)
			
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
			self.v = volts
			
			
	def setCurrent(self, chan, ma, state=None):
		if state is not None:
			self.setDriving('i' if state=='source' else 'v')
		if ma is not None:
			self.i = ma/-1000.0
		
	def start(self, server):
		server.poll(self.poll)
		
	def stop(self):
		self.setCurrent(None, 0)
		
	def poll(self):
		data =  self.update()
		self.ifilt = self.ifilt*0.3 + data[1]*0.7
		return [
			(self.voltageChan, data[0]),
			(self.currentChan, self.ifilt*1000),
			(self.powerChan, abs(data[0] * self.ifilt)),
			(self.resistanceChan, abs(data[0]/self.ifilt)),
			#(self.aiChan, data[2]),
		]

if __name__ == '__main__':
	parser = OptionParser()
	parser.add_option("--cee",  action="store_true", dest="cee")
	(options, args) = parser.parse_args()
	if options.cee:
		vlimit = (-5, 5)
	else:
		vlimit = (-10, 10)
	dev = ModconSMU(vlimit)
	server = pixelpulse.DataServer(dev)
	server.start()
