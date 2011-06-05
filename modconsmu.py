# -*- coding: utf8 -*-
#Ian Daniher - Mar11-17 2011

import sys
import usb.core
import atexit
import livedata

class ModconSMU(livedata.Device):
	vReqs = {'UPDATE' : 1, 
			'SET_DIGOUT' : 2, 
			'GET_DAC_VALS' : 3,
			'SET_DAC_VALS' : 4,
			'GET_VADC_VALS' : 5,
			'GET_IADC_VALS' : 7,
			'GET_RES_VAL' : 9,
			'GET_NAME' : 11,
			'SET_NAME' : 12}
	
	def __init__(self):
		self.voltageChan =    livedata.AnalogChannel('Voltage',     'V',  -10,  10,   'source',  showGraph=True, onSet=self.setVoltage)
		self.currentChan =    livedata.AnalogChannel('Current',     'mA', -200, 200,  'measure', showGraph=True, onSet=self.setCurrent)
		self.resistanceChan = livedata.AnalogChannel('Resistance',  u'Ω', 0,    2000, 'computed')
		self.powerChan =      livedata.AnalogChannel('Power',        'W', 0,    2,    'computed')
		self.aiChan =         livedata.AnalogChannel('Voltage(AI0)', 'V', 0,    4.096, 'input')
		self.channels = [self.voltageChan, self.currentChan, self.resistanceChan,
		                 self.powerChan, self.aiChan]
	
	
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
		atexit.register(self.setCurrent, ma = 0)

	def sign(self, x):
		"""Undo two's complement signing."""
		if x > 32767:
			return 65536-x
		else:
			return x

	def update(self, mod = 1):
		"""updates smu target V/I, returns actual V/I"""
		if self.driving == 'v':
			value = int(round(self.zeroV - self.v/self.scaleFactorV))
			if cmp(value, 0) == -1:
				value = int(round(self.v/self.scaleFactorV - self.zeroV))
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
			
	def setVoltage(self, volts):
		self.v = volts
		if self.driving != 'v':
			self.driving = 'v'
			self.updateNeeded = True
			self.currentChan.setState('measure')
			self.voltageChan.setState('source')
			
	def setCurrent(self, ma):
		self.i = ma/-1000.0
		if self.driving != 'i':
			self.driving = 'i'
			self.updateNeeded = True
			self.currentChan.setState('source')
			self.voltageChan.setState('measure')
		
	def start(self, server):
		server.poll(self.poll)
		
	def poll(self):
		data = self.update()
		return [
			(self.voltageChan, data[0]),
			(self.currentChan, data[1]*1000),
			(self.powerChan, abs(data[0] * data[1])),
			(self.resistanceChan, abs(data[0]/data[1])),
			(self.aiChan, data[2]),
		]

if __name__ == '__main__':
	dev = ModconSMU()
	server = livedata.DataServer(dev)
	server.start()
