import serial, os

class Serial(object):	
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
	
	def __init__(self, port='/dev/ttyUSB1', speed=115200, nchannels=6, max=5.0, inRange=1024, units='V'):
		self.channels = [{
				'name': 'time',
				'displayname': 'Time',
				'units': 's',
				'type': 'linspace',
				'axisMin': -30,
				'axisMax': 'auto',
			}]
		self.config = {'channels': self.channels}
		
		self.nchannels = nchannels
		self.max = max
		self.inRange = inRange
		self.units = units
		
		for i in range(self.nchannels):
			self.channels.append({
				'name': 'c%d'%i,
				'displayname': 'Analog %d'%i,
				'units': self.units,
				'type': 'linspace',
				'axisMin': 0,
				'axisMax': self.max,
			})
		
		self.port = serial.Serial(port, speed, timeout=0)
		
	def getConfig(self):
		return self.config
		
	def getData(self, t):
		lines = self.port.read(4096).split('\r\n')
		
		data = None
		while len(lines):
			line = lines.pop()
			data = line.split()
			if len(data) >= self.nchannels:
				break
			
		if data:
			packet = {'time':t}
			for pt, name in zip(data[0:self.nchannels], range(self.nchannels)):
				packet["c%d"%name] = float(pt)/self.inRange * self.max
			print packet
			return packet
		else:
			return None
			
		
	def onSet(self, vals):
		pass

def getDevices():
	if os.path.exists('/dev/ttyUSB1'):
		return [Serial()]
	else:
		return []
