#!/usr/bin/env python2
# Arduino Firmata driver for Pixelpulse
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>

from optparse import OptionParser
import time
import tornado_serial
import pixelpulse

ANALOG_MESSAGE = 0xE0
DIGITAL_MESSAGE = 0x90
ANALOG_REPORT = 0xC0
DIGITAL_REPORT = 0xD0
SYSEX_START = 0xF0
SYSEX_END = 0xF7
SET_PIN_MODE = 0xF4
CMD_RESET = 0xff
SAMPLING_INTERVAL = 0x7A
CMD_VERSION = 0xF9

sample_interval_ms = 50

class FirmataDevice(pixelpulse.Device):
	def __init__(self, port='/dev/ttyUSB0', dpins=[], apins=[]):
		self.analogChannels = {}
		for n, pin in enumerate(apins):
			ch = pixelpulse.AnalogChannel('A%i'%pin, 'V', 0.0, 5.0, showGraph=(n<=1))
			ch.pin = pin
			ch.value = 0.0
			self.analogChannels[pin] = ch
			
		self.digitalChannels = {}
		for n, pin in enumerate(dpins):
			ch = pixelpulse.DigitalChannel('D%i'%pin, 
			                             showGraph=(n<=1),
			                             stateOptions=['input', 'output', 'pullup'], 
			                             onSet=self.digitalSet) 
			ch.pin = pin
			ch.value = 0.0
			self.digitalChannels[pin] = ch
			
		self.channels = self.analogChannels.values() + self.digitalChannels.values()
		self.port = port
		
		# store incoming commands until they are complete and can be process
		self.buf_cmd = None
		self.buf_low = None
		self.sysex = False
		
		self.digitalOut = [0,0]
		
	def start(self, server):
		def onData(d):
			for c in d:
				if self.sysex:
					if ord(c) == SYSEX_END:
						self.sysex = False
					continue
				if ord(c) and ord(c) == SYSEX_START:
					self.sysex = True
				elif ord(c) & 0x80:
					# New command byte
					self.buf_cmd = ord(c)
					self.buf_low = None
				elif not self.buf_cmd:
					# We started in the middle of a commmand. Ignore until re-sync
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
						self.analogChannels[chan].value =  5.0 * data/1024.0
					elif self.buf_cmd & 0xf0 == DIGITAL_MESSAGE:
						for ch in self.digitalChannels.values():
							if ch.pin//8 == chan and ch.state!='output':
								ch.value = bool(data & 1<<(ch.pin%8))
					elif self.buf_cmd == CMD_VERSION:
						print "Detected Firmata V%i.%i"%(self.buf_low,hi)
						self.setup_report()
					else:
						print 'Received unknown message', hex(self.buf_cmd), hex(self.buf_low), hex(hi)
					self.buf_cmd = self.buf_low = None
					
		self.serial = tornado_serial.TornadoSerial(self.port, 57600, onData, on_error=server.quit)
		self.setup_report()
		server.poll(self.onPoll)
		
	def onPoll(self):
		return   [(ch, ch.value) for ch in self.digitalChannels.values()] \
		       + [(ch, ch.value) for ch in self.analogChannels.values()]
		
	def setup_report(self):
		""" Configure Firmata to report values for selected pins """
		self.serial.write(chr(CMD_RESET))
		self.serial.flush()
			
		self.serial.write(chr(SYSEX_START) + chr(SAMPLING_INTERVAL) + chr(sample_interval_ms) + chr(0) + chr(SYSEX_END))
		
		for i in range(2):
			self.serial.write(chr(DIGITAL_REPORT|i) + chr(1))
		for i in self.analogChannels.keys():
			self.serial.write(chr(ANALOG_REPORT|i) + chr(1))
			
		for i in self.digitalChannels.keys():
			self.setMode(i, False)
			
	def setMode(self, pin, isOutput):
		""" Set a digital pin as an input or output """
		self.serial.write(chr(SET_PIN_MODE) + chr(pin) + chr(isOutput))
		#print 'setMode', pin, isOutput
		
	def digitalSet(self, channel, val, state):
		""" Handle a state or value change from the UI """
		if state == 'output':
			if val is not None:
				v = bool(val)
				channel.value = v
			else:
				# write input value to output to maintain current level
				v = channel.value
		elif state == 'input':
			v = False
		elif state == 'pullup':
			v = True
		else:
			print "invalid state '%s'"%state
			return
			
		if channel.state != state:
			channel.setState(state)
			self.setMode(channel.pin, state=='output')
			
		if channel.pin < 8:
			port = 0
			i = channel.pin
		else:
			port = 1
			i = channel.pin - 8
			
		if v is True:
			self.digitalOut[port] |= (1<<i)
		elif v is False:
			self.digitalOut[port] &= ~(1<<i)
			
		#print 'setOut', port, i, v, hex(self.digitalOut[port])
			
		self.serial.write(chr(DIGITAL_MESSAGE | port) 
		                + chr(self.digitalOut[port] & 0x7f) 
		                + chr(self.digitalOut[port] >> 7))

def parse_pin_spec(s, dpins=[], apins=[]):
        """ Parse pin specifications such as a0 (analog 0), d4 (digital 4), D3, d2-5 """
	if s[0].lower() == 'd':
		l = dpins
		nmin = 2
		nmax = 13
	elif s[0].lower() == 'a':
		l = apins
		nmin = 0
		nmax = 5
	else:
		raise ValueError("Invalid pin specification %s"%s)
	
	if '-' in s:
	    p = s[1:].split('-')
	    if not len(p) == 2:
	        raise ValueError("Invalid range")
	    lo = int(p[0])
	    hi = int(p[1])
	    if nmin<=lo<= nmax and nmin<=hi<=nmax:
	        l.extend(range(lo, hi+1))
	    else:
	        raise ValueError("Specification %s out of range %i <= n <= %i"%(s, nmin, nmax))
	else:
	    n = int(s[1:])
	    if nmin <= n <= nmax:
	        l.append(n)
	    else:
	        raise ValueError("Pin %s out of range %i <= n <= %i"%(s, nmin, nmax))
	        
	return dpins, apins
	
		
if __name__ == '__main__':
	op = OptionParser()
	op.add_option("-p",  dest="port", help="Use Arduino attached to port PORT", metavar="PORT", default="auto")
	options, args = op.parse_args()
	port = tornado_serial.check_port(options.port)
	
	apins = []
	dpins = []
	for s in args:
		parse_pin_spec(s, dpins, apins)
		
	if not apins and not dpins:
		print "Using default pins D2-4 D13 A0-3"
		dpins = range(2, 4+1) + [13]
		apins = range(3+1)
	
	dev = FirmataDevice(port, dpins, apins)
	server = pixelpulse.DataServer(dev)
	server.start()
