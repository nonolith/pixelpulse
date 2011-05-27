import math, time
import livedata

cos = livedata.AnalogChannel(
	name='cos',
	displayname='Cosine',
	unit='V',
	min=-1.0,
	max=1.0,
	showGraph=True,
)

sin = livedata.AnalogChannel(
	name='sin',
	displayname='Sine',
	unit='A',
	min=-1.0,
	max=1.0,
	showGraph=True,
)

server = livedata.DataServer([cos, sin])

def update():
	server.data([
		(cos, math.cos(time.time())),
		(sin, math.sin(time.time())),
	])

server.poll(update)
server.start()

