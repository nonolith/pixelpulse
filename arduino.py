import livedata
import tornado_serial

class ArduinoDevice(livedata.Device):
	def __init__(self, port='/dev/ttyUSB0'):
		self.analogChannels = [livedata.AnalogChannel('A%i'%i, 'V', 0.0, 5.0, showGraph=i<=3) for i in range(6)]
		self.channels = self.analogChannels
		self.port = port
		
	def start(self, server):
		def line(text):
			readings = [float(i)/1024.0*5.0 for i in text.split()]
			server.data(zip(self.analogChannels, readings))
		
		self.serial = tornado_serial.TornadoLineSerial(self.port, 115200, line)
		
if __name__ == '__main__':
	dev = ArduinoDevice()
	server = livedata.DataServer(dev)
	server.start()
