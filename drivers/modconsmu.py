# -*- coding: utf8 -*-
#Ian Daniher - Mar11-17 2011

import sys
import usb.core
import atexit

class ModconSMU(object):
	vReqs = {'UPDATE' : 1, 
			'SET_DIGOUT' : 2, 
			'GET_DAC_VALS' : 3,
			'SET_DAC_VALS' : 4,
			'GET_VADC_VALS' : 5,
			'GET_IADC_VALS' : 7,
			'GET_RES_VAL' : 9,
			'GET_NAME' : 11,
			'SET_NAME' : 12}
	
	CONFIG = {
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

	def sign(self, x):
		"""Undo two's complement signing."""
		if x > 32767:
			return 65536-x
		else:
			return x

	def __init__(self):
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
		atexit.register(self.setCurrent, amps = 0)

	def update(self, mod = 1):
		"""updates smu target V/I, returns actual V/I"""
		if self.driving == 'v':
			value = int(self.zeroV - self.v/self.scaleFactorV)
			direction = 0
		elif self.driving == 'i':
			value = int(self.zeroI + self.i * 10000)
			direction = 1
		else:
			print("bad type")
		if self.updateNeeded == 1:
			self.dev.ctrl_transfer(bmRequestType = 0x40, bRequest = self.vReqs['SET_DIGOUT'], wValue = direction, wIndex = 0, data_or_wLength = [0]*12)
			self.updateNeeded = 0
		print value
		data = self.dev.ctrl_transfer(bmRequestType = 0xC0, bRequest = self.vReqs['UPDATE'], wValue = value, wIndex = 0, data_or_wLength = 12)
		retVolt = ((data[0]|data[1]<<8)-self.VADC)/self.VADCGAIN
		retAmp = ((data[4]|data[5]<<8)-self.IADC)/(self.IADCGAIN*self.RES)
		modVolt = (data[6]|data[7]<<8)*(4.096/1023)
		if mod:
			return (retVolt, retAmp, modVolt)
		else:
			return (retVolt, retAmp)
			
	def setVolts(self, volts):
		if self.driving == 'v':
			self.v = volts
		elif self.driving == 'i':
			self.v = volts
			self.driving = 'v'
			self.updateNeeded = True
			
	def setCurrent(self, amps):
		if self.driving == 'i':
			self.i = amps
		elif self.driving == 'v':
			self.i = amps
			self.driving = 'i'
			self.updateNeeded = True
			
	def getConfig(self):
		return self.CONFIG
		
	def getData(self, t):
		data = self.update()
		return {
			'time': t,
			'voltage': data[0],
			'current': data[1]*1000,
			'power': abs(data[0] * data[1]),
			'resistance': abs(data[0]/data[1]),
			'voltage(AI0)': data[2],
			'_driving': 'current' if self.driving=='i' else 'voltage'
		}
		
	def onSet(self, vals):
		for prop, val in vals.iteritems():
			if prop == 'voltage':
				self.setVolts(val)
			elif prop == 'current':
				self.setCurrent(val/1000.0)

def getDevices():
	try: 
		return [ModconSMU()]
	except IOError:
		return []
