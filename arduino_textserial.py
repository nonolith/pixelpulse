#!/usr/bin/env python2
# Example serial text input driver for Pixelpulse
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>

import pixelpulse
import tornado_serial

class ArduinoDevice(pixelpulse.Device):
	def __init__(self, port='/dev/ttyUSB0'):
		self.analogChannels = [pixelpulse.AnalogChannel('A%i'%i, 'V', 0.0, 5.0, showGraph=i<=3) for i in range(6)]
		self.channels = self.analogChannels
		self.port = port
		
	def start(self, server):
		def line(text):
			readings = [float(i)/1024.0*5.0 for i in text.split()]
			server.data(zip(self.analogChannels, readings))
		
		self.serial = tornado_serial.TornadoLineSerial(self.port, 115200, line)
		
if __name__ == '__main__':
	dev = ArduinoDevice()
	server = pixelpulse.DataServer(dev)
	server.start()
