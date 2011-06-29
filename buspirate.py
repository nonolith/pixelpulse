from optparse import OptionParser
import time
import tornado_serial
import livedata

channel_masks = {
	'CS':   (1<<0),
	'MISO': (1<<1),
	'CLK':  (1<<2),
	'MOSI': (1<<3),
	'AUX':  (1<<4),
}

class BusPirateDevice(livedata.Device):
	def __init__(self, port='/dev/ttyUSB0', colors=None, pullups=True):
		opts = dict(
			onSet=self.onSet, stateOptions=['input','output']
		)
		
		self.digitalChannels = [
			livedata.DigitalChannel(name, showGraph=True, color=colors[name], **opts)
			for name in ['AUX','MOSI', 'CLK', 'MISO', 'CS']]
			
		self.channels = self.digitalChannels
		self.port = port
		self.recv_mode = 'init'
		
		self.output_state = (1<<7)|(1<<6)
		if pullups:
			self.output_state |= (1<<5)
		self.output_mode = 0x5f # all pins input
		self.initData = ''
		
	def start(self, server):
		def onReceive(data):
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
					out.append((chan, bool(data & mask)))
				server.data(out)
				
		self.serial = tornado_serial.TornadoSerial(self.port, 115200, onReceive, on_error=server.quit)
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
		self.serial.write(chr(self.output_state) + chr(self.output_mode))
		
	def onSet(self, chan, val, state):
		mask = channel_masks[chan.name]
		self.output_mode &= ~mask
		
		if state == 'output':
			self.output_mode &= ~mask
			chan.setState('output')
		elif state == 'input':
			self.output_mode |= mask
			chan.setState('input')
		
		if state == 'output' and val is not None:
			if val:
				self.output_state |= mask
			else:
				self.output_state &= ~mask
	
COLORS = {
	'sparkfun': {
		'CS':   'red',
		'MISO': 'brown',
		'CLK':  '#eeee00',
		'MOSI': 'orange',
		'AUX':  '#00ff00',
	},
	'seeed': {
		'CS':   '#bbb',
		'MISO': 'black',
		'CLK':  '#ff00ff',
		'MOSI': '#888',
		'AUX':  'blue',
	}
}		
		
if __name__ == '__main__':
	op = OptionParser()
	op.add_option("-p",  dest="port", help="Use BusPirate attached to port PORT", metavar="PORT", default="auto")
	op.add_option("-c", dest="colors", type="choice", choices=COLORS.keys(), default="seeed",
		help="Wire colors - 'seeed' or 'sparkfun'", metavar="MODEL")
	op.add_option("-d", dest="nopullups", action="store_true", help="Disable pullups",)
	(options, args) = op.parse_args()
	if options.port == 'auto':
		options.port = tornado_serial.default_port()
		if not options.port:
			print "No serial port found. Use -p PORT to specify"
			exit()
		else:
			print "Using port", options.port
	
	dev = BusPirateDevice(options.port, COLORS[options.colors], not options.nopullups)
	server = livedata.DataServer(dev)
	server.start()
