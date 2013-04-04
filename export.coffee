
window.downloadCSV = (columns) -> # [{name, units, precision, data}]
	rows = for i in [0...columns[0].data.length]
		(data[i].toFixed(precision) for {data, precision} in columns).join(",") + "\n"

	header = ("\"#{name} (#{units})\"" for {name, units} in columns).join(",") + "\n"
	rows.unshift header

	downloadFile(rows, "text/csv", "export#{+new Date()}.csv" )		

window.downloadFile = (data, type, filename) ->
	url = window.URL.createObjectURL new Blob(data, {type})
	a = document.createElement('a')
	a.href =  url
	a.download = filename
	a.style.display = 'none';
	document.body.appendChild(a);
	a.click();
	document.body.removeChild(a)
	setTimeout((->window.URL.revokeObjectURL(url)), 10)

		