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
			
	def getConfig(self):
		return self.CONFIG
		
	def getData(self, t):
		return {
			'time': t,
			'voltage': math.sin(t)*5,
			'current': math.cos(t)*150,
			'_driving': 'voltage'
		}
		
	def onSet(self, vals):
		pass

def getDevices():
	return [Dummy()]
