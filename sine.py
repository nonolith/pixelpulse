import math, time
import livedata

class SineDevice(livedata.Device):
	def __init__(self):
		self.cos = livedata.AnalogChannel(
			name='Cosine',
			unit='V',
			min=-1.0,
			max=1.0,
			showGraph=True,
		)

		self.sin = livedata.AnalogChannel(
			name='Sine',
			unit='A',
			min=-1.0,
			max=1.0,
			showGraph=True,
		)
		
		self.channels = [self.sin, self.cos]
		
	def start(self, server):
		server.poll(self.update)
		
	def update(self):
		return [
			(self.cos, math.cos(time.time())),
			(self.sin, math.sin(time.time())),
		]
		
if __name__ == '__main__':
	dev = SineDevice()
	server = livedata.DataServer(dev)
	server.start()
