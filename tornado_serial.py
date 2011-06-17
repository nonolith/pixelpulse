import serial
from tornado.ioloop import IOLoop

class TornadoSerial(object):
	def __init__(self, port=None, baud=9600, on_receive=None, on_error=None, *args):
		self.on_receive = on_receive
		self.on_error = on_error
		self.serial = serial.Serial(port, baud, timeout=0, *args)
		self.io_loop = IOLoop.instance()
		self.io_loop.add_handler(
						self.serial.fileno(), self._serial_event,
						IOLoop.READ)
	
	def _serial_event(self, fd, events):
		try:
			data = self.serial.read(self.serial.inWaiting())
		except IOError, e:
			print "Serial IO error", e
			if self.on_error:
				self.on_error(e)
		else: 
			if data:
				self.on_receive(data)
			
	def write(self, data):
		self.serial.write(str(data))
		
	def flush(self):
		self.serial.flushInput()
		self.serial.flushOutput()
		
class TornadoLineSerial(TornadoSerial):
	def __init__(self, port=None, baud=9600, on_receive=None, on_error=None, line_sep='\r\n', *args):
		super(TornadoLineSerial, self).__init__(port, baud, self.on_receive, on_error, *args)
		self._on_receive = on_receive
		self.line_sep = line_sep
		self.buffer = ""
		
	def on_receive(self, text):
		self.buffer += text
		while self.line_sep in self.buffer:
			i = self.buffer.index(self.line_sep)
			line = self.buffer[:i]
			self.buffer = self.buffer[i+len(self.line_sep):]
			self._on_receive(line)
