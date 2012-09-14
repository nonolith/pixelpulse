
window.exportCSV = (start, length, maxCount, cb) ->
	streams = []
	for _, channel of server.device.channels
		streams.push(stream) for _, stream of channel.streams

	df = Math.max(Math.round(length / maxCount), 1)
	listener = new server.DataListener(server.device, streams)
	listener.len = listener.count = Math.floor(length / df)
	listener.startSample = start
	listener.decimateFactor = df

	#console.log('export', start, length, df, listener.len, listener)

	listener.submit()

	listener.done.listen ->
		#console.log('export complete', listener)
		rows = for i in [0...listener.xdata.length]
			d = [(i*server.device.sampleTime*df).toFixed(7)]
			for dataArr in listener.data
				d.push(dataArr[i].toFixed(4))
			d.join(',') + '\n'

		header = ("\"#{i.displayName} (#{i.units})\"" for i in streams).join(",")
		header = "\"Time (s)\",#{header}\n"
		rows.unshift(header)

		blob = new Blob(rows, {"type":"text/csv"})
		objectURL = window.webkitURL.createObjectURL(blob)
		cb(objectURL)
		


		