# Utility functions for displaying quantities for human consumption

exports = exports or (window.unitlib = {})

# Get a SI scale prefix for a value and the corresponding scale factor
exports.unitPrefixScale = unitPrefixScale = (v) ->
	if v == 0 then return ['', 1]
	v = Math.abs(v)
	m = Math.floor(Math.log(v)/Math.LN10)
	m = Math.floor(m/3)*3

	unit = switch m
		when 12  then 'T'
		when 9   then 'G'
		when 6   then 'M'
		when 3   then 'k'
		when 0   then ''
		when -3  then 'm'
		when -6  then '\u00B5'
		when -9  then 'n'
		when -12 then 'p'

	return [unit, Math.pow(10, m)]

window.arange = arange = (lo, hi, step) ->
	ret = new Array(Math.ceil((hi-lo)/step+1))
	for i in [0...ret.length]
		ret[i] = lo + i*step
	return ret

# Generate a grid for the specified range
# min, max: the bounds of the window for which to generate range ticks
# countHint: approximate number of ticks within the window
# limitMin, limitMax: additional limits on the generated grid. Does not effect the
#                     calculation of the grid, but ticks outside the limits are removed
exports.grid = grid = (min, max, countHint=10, limitMin=-Infinity, limitMax=Infinity) ->
	# Based on code from d3.js
	span = max-min
	step = Math.pow(10, Math.floor(Math.log(span / countHint) / Math.LN10))

	err = countHint / span * step;

	# Filter ticks to get closer to the desired count.
	if err <= .15 then step *= 10
	else if err <= .35 then step *= 5
	else if err <= .75 then step *= 2

	# Round start and stop values to step interval.
	gridMin = Math.ceil( Math.max(min, limitMin) / step) * step
	gridMax = Math.floor(Math.min(max, limitMax) / step) * step # inclusive

	return arange(gridMin, gridMax, step)

UNICODE_SUPERSCRIPT = String.fromCharCode(8304, 185, 178, 179, 8308, 8309, 8310, 8311, 8312, 8313)

# Generate a logarithmic grid
exports.logGridLabels = (powMin, powMax, unit) ->
	out = []

	for i in [powMin..powMax]
		for j in [1..9]
			if j == 1
				out.push([i, "10#{UNICODE_SUPERSCRIPT[i]}"])
			else
				out.push([i + Math.log(j)/Math.LN10, ''])

	out[0][1] += " " + unit if unit

	return out


# Generate a grid for the specified range, with corresponding labels
# parameters: see grid()
# unit: the base unit to use
exports.gridLabels = gridLabels = (min, max, unit='', countHint=10, useScale=true, limitMin, limitMax, prescale=1) ->
	[unitprefix, scale] = if useScale then unitPrefixScale((max-min)/2/prescale) else ['', 1]
	scale *= prescale
	g = grid(min, max, countHint, limitMin, limitMax)
	digits = Math.max(Math.ceil(-Math.log(Math.abs((g[1]-g[0])/scale))/Math.LN10), 0)
	hasZero = 0 in g

	for v, i in g
		num = (v/scale).toFixed(digits)
		hasunit = if hasZero
						v == 0
					else
						i == 0
		showunit = if unit and hasunit then "#{unitprefix}#{unit}" else ''
		[v, "#{num}#{showunit}"]
