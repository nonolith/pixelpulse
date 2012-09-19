
latestFirmware = '1.2'
latestConnect = '1.3'

# params: object containing
#	app: name of app
#	model: device model to target
#	reset: function called to reset all state
#	updateDevsMenu: function called with a list to enable the device chooser
#	initDevice: start with a device

session = window.session = (params) ->
	session.params = params

	if !window.WebSocket
		session.overlay "#{session.opts.app} requires WebSockets and currently only works in Chrome and Safari"
		return

	server.connect()
	
	hasConnected = no
	
	server.connected.listen ->
		hasConnected = yes

	server.disconnected.listen ->
		$("#error-overlay").children().hide()
		$('#connectError').show()
		$('#error-overlay').fadeIn(300)
		track_feature("disconnected")
		session.params.reset()

	server.devicesChanged.listen (l) ->
		session.availDevs = (d for d in server.devices when d.model == session.params.model)
		session.params.updateDevsMenu(session.availDevs)

		if not server.device
			session.chooseDevice()


session.chooseDevice = ->
	if session.availDevs.length == 1
		session.initDevice(session.availDevs[0])

	else if session.availDevs.length > 1
		# Show the device chooser dialog
		# TODO: update dialog if list changes

		$("#error-overlay").children().hide()
		$('#chooseDevices').show()
		
		ul = $('#chooseDevices ul').empty()
		for d in session.availDevs then do (d) ->
			ul.append $("<li>").text(d.serial).click ->
				session.initDevice(d)
		
		$('#error-overlay').fadeIn(300)

	else
		session.overlay "No devices found"
			
session.parseFlags = (flags = {}) ->

	if navigator.userAgent.indexOf("Windows") >= 0 then $(document.body).addClass('os-windows')
	if navigator.userAgent.indexOf("Linux") >= 0  then $(document.body).addClass('os-linux')
	if navigator.userAgent.indexOf("Mac") >= 0 then $(document.body).addClass('os-mac')

	#URL params
	window.flags = flags
	for flag in document.location.hash.slice(1).split('&')
		flags[flag]=true

	if init_ga and not flags.noga
		init_ga()

session.initDevice = (dev) ->
	if server.device and dev.id == server.device.id
		session.overlay()
		return

	session.overlay("Loading Device...")

	d = server.selectDevice(dev)

	session.checkUpdate(server.version, dev.fwVersion)	

	d.changed.listen ->
		session.params.reset()
		session.overlay()
		session.params.deviceChanged(d)

	d.removed.listen ->
		session.params.deviceRemoved()
		session.params.reset()
		session.chooseDevice()
		
	session.params.initDevice(d)
					
session.overlay = (message) ->
	if not message
		$("#error-overlay").hide()
	else
		$("#error-overlay").children().hide()
		$("#error-status").show().text(message)
		$("#error-overlay").fadeIn(300)

session.checkUpdate =  (connectVersion, fwVersion) ->
	connectUpdate = (latestConnect > connectVersion)
	fwUpdate = (latestFirmware > fwVersion)

	connectURL = 'http://www.nonolithlabs.com/connect/'
	fwURL = 'http://www.nonolithlabs.com/cee/firmware'

	if connectUpdate or fwUpdate
		plural = (connectUpdate and fwUpdate)
		msg = "<strong>Update#{if plural then 's' else ''} Available!</strong> "
		msg += "<a href='#{connectURL}'>Nonolith Connect #{latestConnect}</a> " if connectUpdate
		msg += "and " if plural
		msg += "<a href='#{fwURL}'>CEE Firmware #{latestFirmware}</a> " if fwUpdate
		msg += " &mdash; " + session.params.updateMessage if session.params.updateMessage
		hide = $("<span class='close'>&times</span>").click(->$(this).parent().hide())
		$('#update-notify').html(msg).append(hide).show()
		$('#update-notify').find('a').attr('target', 'pp-update')
	else
		$('#update-notify').hide()




		