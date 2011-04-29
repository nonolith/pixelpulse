import math

class Dummy(object):	
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
		]
	}
	
	def __init__(self):
		self.r = 100.0
		self.c = 100e-4
		self.q = 0.0
		self.setCurrent = None
		self.setVoltage = 0
		self.lastTime = 0
			
	def getConfig(self):
		return self.CONFIG
		
	def getData(self, t):
		dt = self.lastTime-t
		if self.setCurrent is not None:
			current = self.setCurrent
			voltage = self.q/self.c
			
			if (voltage>=10 and current<0) or (voltage<=-10 and current>0):
				current = 0
			
			self.q += current*dt
		elif self.setVoltage is not None:
			voltage = self.setVoltage
			current = -(self.setVoltage-self.q/self.c)/self.r
			self.q += current*dt
			
		self.lastTime = t
		return {
			'time': t,
			'voltage': voltage,
			'current': current*1000.0,
			'_driving': 'voltage' if self.setVoltage else 'current'
		}
		
	def onSet(self, vals):
		for k,v in vals.iteritems():
			if k == 'current':
				self.setCurrent = v/1000.0
				self.setVoltage = None
			elif k == 'voltage':
				self.setVoltage = v
				self.setCurrent = None	

def getDevices():
	return [Dummy()]
