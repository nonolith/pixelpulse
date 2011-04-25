from __future__ import division

try:
	from quantities import degC, ohm
except:
	degC = ohm = 1

class RTD:
	def __init__(self):
		self.A = 3.9083 * 10**-3 * degC**-1
		self.B = -5.775 * 10**-7 * degC**-2
		self.Ri = 100 * ohm
		self.R1 = 100 * ohm
	def getTemp(self, Req):
		"""convert equivalent resistance(as seen by the SMU) to temperature"""
		Rt = Req * self.R1 / (self.R1 - Req)
		dR = Rt/self.Ri
		t = (dR-1)/self.A
		return t
	def getTarget(self, t):
		"""get theoretical resistance for a target temperature"""
		dRTheory = 1 + self.A * t + self.B * t**2
		R0 = dRTheory * self.Ri
		Req = (R0 * self.R1)/(R0 + self.R1)
		return Req
