import livedata
import tornado_serial
import time

channel_masks = {
	'CS':   (1<<0),
	'MISO': (1<<1),
	'CLK':  (1<<2),
	'MOSI': (1<<3),
	'AUX':  (1<<4),
}

class BusPirateDevice(livedata.Device):
	def __init__(self, port='/dev/ttyUSB0'):
		self.digitalChannels = [
			livedata.AnalogChannel(name, 'V', 0.0, 1.0, showGraph=True)
			for name in ['AUX','MOSI', 'CLK', 'MISO', 'CS']]
			
		self.channels = self.digitalChannels
		self.port = port
		self.recv_mode = 'init'
		
		self.output_state = (1<<7)|(1<<6)|(1<<5)
		self.output_mode = 0x5f # all pins input
		self.initData = ''
		
	def start(self, server):
		def onReceive(data):
			print '>', data
		
			if self.recv_mode == 'init':
				self.initData += data
				if 'BBIO1' in self.initData:
					print "BusPirate initialized"
					time.sleep(0.1)
					self.serial.flush()
					self.recv_mode = 'input'
					server.poll(self.onPoll)
			elif self.recv_mode == 'input':
				data = ord(data[0])
				out = []
				for chan in self.digitalChannels:
					mask = channel_masks[chan.name]
					out.append((chan, float(bool(data & mask))))
				server.data(out)
				
		self.serial = tornado_serial.TornadoSerial(self.port, 115200, onReceive)
		self.enter_bbio()
				
		
	def enter_bbio(self):
		self.reset()
		self.serial.write('\r\n'*10 + '#')
		time.sleep(0.1)
		self.serial.write('\0'*20)
		self.recv_mode = 'init'
		
	def reset(self):
		self.serial.write('\x0f')
		time.sleep(0.1)
		self.serial.flush()
		
	def onPoll(self):
		print repr(chr(self.output_state) + chr(self.output_mode))
		self.serial.write(chr(self.output_state) + chr(self.output_mode))
		
	
		
		
if __name__ == '__main__':
	dev = BusPirateDevice()
	server = livedata.DataServer(dev)
	server.start()
