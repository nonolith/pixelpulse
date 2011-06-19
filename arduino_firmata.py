import livedata
import tornado_serial
import time

ANALOG_MESSAGE = 0xE0
DIGITAL_MESSAGE = 0x90
ANALOG_REPORT = 0xC0
DIGITAL_REPORT = 0xD0
SYSEX_START = 0xF0
SYSEX_END = 0xF7
SET_PIN_MODE = 0xF4
CMD_RESET = 0xff
SAMPLING_INTERVAL = 0x7A

sample_interval_ms = 50

class FirmataDevice(livedata.Device):
	def __init__(self, port='/dev/ttyUSB0'):
		self.analogChannels = [livedata.AnalogChannel('A%i'%i, 'V', 0.0, 5.0, showGraph=i<=1) for i in range(6)]
		
		so = ['input', 'output', 'pullup']
		self.digitalPins = range(2, 9)
		self.digitalChannels = [
			livedata.DigitalChannel('D%i'%i, showGraph=i<4, stateOptions=so, onSet=self.digitalSet) 
			for i in self.digitalPins]
			
		self.channels = self.analogChannels + self.digitalChannels
		self.port = port
		
		self.buf_cmd = None
		self.buf_low = None
		
		self.digitalValues = [0] * len(self.digitalChannels)
		self.analogValues = [0] * len(self.analogChannels)
		
		self.digitalOut = [0,0]
		
	def start(self, server):
		def onData(d):
			for c in d:
				if ord(c) & 0x80:
					#New command byte
					self.buf_cmd = ord(c)
					self.buf_low = None
				elif not self.buf_cmd:
					continue
				elif self.buf_low is None:
					# 2nd byte of report. save it
					self.buf_low = ord(c)
				else:
					# final byte of report. extract and use value
					hi = ord(c)
					chan = self.buf_cmd & 0x0f
					data = (hi<<7)|(self.buf_low&0x7f)
					if self.buf_cmd & 0xf0 == ANALOG_MESSAGE:
						self.analogValues[chan] =  5.0 * data/1024.0
					elif self.buf_cmd & 0xf0 == DIGITAL_MESSAGE:
						print 'digital', chan, data
						if chan == 0:
							for i, pin in enumerate(self.digitalPins):
								if i<8 and self.digitalChannels[i].state!='output':
									self.digitalValues[i] = bool(data & 1<<pin)
					else:
						print 'unknown', hex(self.buf_cmd), hex(self.buf_low), hex(hi)
					self.buf_cmd = self.buf_low = None
					
		self.serial = tornado_serial.TornadoSerial(self.port, 57600, onData)
		self.setup_report()
		server.poll(self.onPoll)
		
	def onPoll(self):
		return zip(self.digitalChannels, self.digitalValues) + zip(self.analogChannels, self.analogValues)
		
	def setup_report(self):
		self.serial.write(chr(CMD_RESET))
		
		for i in self.digitalPins:
			self.setMode(i, False)
			
		self.serial.write(chr(SYSEX_START) + chr(SAMPLING_INTERVAL) + chr(sample_interval_ms) + chr(0) + chr(SYSEX_END))
		
		for i in range(2):
			self.serial.write(chr(DIGITAL_REPORT|i) + chr(1))
		for i in range(6):
			self.serial.write(chr(ANALOG_REPORT|i) + chr(1))
			
	def setMode(self, pin, isOutput):
		self.serial.write(chr(SET_PIN_MODE) + chr(pin) + chr(isOutput))
		print 'setMode', pin, isOutput
		
	def digitalSet(self, channel, val, state):
		index = self.digitalChannels.index(channel)
		i = self.digitalPins[index]
		if channel.state != state:
			channel.setState(state)
			self.setMode(i, state=='output')
			
		if state == 'output' and val is not None:
			v = bool(val)
			self.digitalValues[index] = v
		elif state == 'input':
			v = False
		elif state == 'pullup':
			v = True
		else:
			return
			
		
		if i < 8:
			port = 0
		else:
			port = 1
			i-=8
			
		print 'setOut', port, i, v
			
		if v is True:
			self.digitalOut[port] |= (1<<i)
		elif v is False:
			self.digitalOut[port] &= ~(1<<i)
			
		self.serial.write(chr(DIGITAL_MESSAGE | port) 
		                + chr(self.digitalOut[port] & 0x7f) 
		                + chr(self.digitalOut[port] >> 7))
		
if __name__ == '__main__':
	dev = FirmataDevice()
	server = livedata.DataServer(dev)
	server.start()
