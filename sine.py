import math, time
import pixelpulse

class SineDevice(pixelpulse.Device):
	def __init__(self):
	
		# Define the channels
		self.cos = pixelpulse.AnalogChannel(
			name='Cosine',
			unit='V',
			min=-1.0,
			max=1.0,
			# Graph is initially shown. If False, the channel will be on the bottom bar
			showGraph=True,
		)

		self.sin = pixelpulse.AnalogChannel(
			name='Sine',
			unit='A',
			min=-1.0,
			max=1.0,
			showGraph=True,
		)
		
		# pixelpulse reads this property to determine which channels to show
		self.channels = [self.sin, self.cos]
		
	def start(self, server):
		""" This method is called by Pixelpulse once the server is started """
		server.poll(self.update) # ask the server to poll our update() method at its default sample rate
		
	def update(self):
		""" Polled to update the data as configured in start(). Returns a list of (channel. value) pairs """
		return [
			(self.cos, math.cos(time.time())),
			(self.sin, math.sin(time.time())),
		]
		
if __name__ == '__main__':
	dev = SineDevice()
	server = pixelpulse.DataServer(dev)
	server.start()
