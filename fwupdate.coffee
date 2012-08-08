# Firmware update
# (C) 2012 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

class FirmwareUpdateApp
	constructor: (params) ->
		@device = null
		@firmware = null

		server.connect()

		server.disconnected.listen ->
			$('#no-devices,#multi-device-note,#device-info').hide()
			$('#no-connect').show()
			track_feature('disconnected')

		if params['image'] == 'custom'
			@startFirmwareSelPage()
		else
			@loadFirmware(params['image'])

	startFirmwareSelPage: ->
		$('#p1 > div').hide()
		$('#upload-firmware').show()

		$('#file').one 'change', (e) =>
			files = e.target.files
			file = files[0]
			reader = new FileReader()
			reader.onload = (e) =>
				try
					json = JSON.parse(reader.result)
				catch error
					console.log(error)
					alert("Invalid JSON", error)
					return
				@firmwareLoaded(json)
			reader.readAsText(file, 'utf-8')

	loadFirmware: (image)->
		if /(\w[\w.]+\/)+\w[\w.]+/.test(image)
			req = $.get('/firmware/'+image, @firmwareLoaded, 'json')
			req.error (e) ->
				alert("Could not load firmware image")
		else
			alert("Invalid firmware image path")

	firmwareLoaded: (@firmware) =>
		console.log("firmwareLoaded", @firmware)

		version = @firmware.fwVersion
		if @firmware.gitVersion
			version = "#{version} (git #{@firmware.gitVersion})"

		$('#available-version').text(version)

		@startDevicePage()

	startDevicePage: ->
		server.devicesChanged.listen(@updateDevices)
		@updateDevices()

	isApplicable: (dev)->
		window.v1 = dev.hwVersion
		window.v2 = @firmware.hwVersion
		console.log(dev)

		if dev.model == @firmware.device_match \ 
		and dev.hwVersion == @firmware.hwVersion
			console.log('match')
			true
		else if dev.model == 'com.nonolithlabs.bootloader'# \
		#and dev.hw_product == @firmware.device \
		#and dev.hw_version == @firmware.hwVersion
			true
		else
			false 

		
	updateDevices: =>
		console.log 'updating device list'
		potentialDevices = (dev for dev in server.devices when @isApplicable(dev))

		$('#p1 > div, #btn_install').hide()
		if potentialDevices.length == 0
			$('#no-devices').show()
			@device = null
		else
			if potentialDevices.length > 1
				$('#multi-device-note').show()
			$('#device-info,#btn_install').show()
			@selectDevice(potentialDevices[0])

	selectDevice: (@device) ->
		if @device.model == 'com.nonolithlabs.cee'
			hardwareDevice = "Nonolith CEE #{@device.hwVersion}"
			[firmwareVersion, gitVersion] = @device.fwVersion.split('/')
			if gitVersion
				firmwareVersion = "#{firmwareVersion} (git #{gitVersion})"
		else if @device.model = 'com.nonolithlabs.bootloader'
			if device.hwVersion == 'unknown'
				hardwareDevice = "Bootloader"
			else
				hardwareDevice = device.hwVersion
			#hardwareDevice = @device.hw_product
			#hardwareVersion = @device.hw_version
			firmwareVersion = 'Unknown (already in bootloader mode)'

		#console.log('device', @device, hardwareDevice, hardwareVersion, firmwareVersion)

		$('#hw-device').text(hardwareDevice)
		$('#current-version').text(firmwareVersion)
		$('#serial').text(device.serial)

		$('#btn_install').one 'click', @startInstall

	startInstall: =>
		track_feature('firmware-update-start')
		server.devicesChanged.unListen(@updateDevices)

		$('.opened').removeClass('opened')
		$('#p2').addClass('opened')
		$('#log').empty()

		log = (m, c='run') ->
			$('#log').append($("<div>").html(m).addClass(c))

		logDone = ->
			$('#log div:last-child').addClass('ok')

		log("Installing firmware #{@firmware.fwVersion}", 'ok')

		serial = @device.serial
		device_conn = null
		firmware = @firmware

		waitForDevice = (serial, cb) ->
			listCb = (devs) ->
				console.log('listCb', devs)
				for i in devs
					if i.serial == serial
						server.devicesChanged.unListen(listCb)
						return cb(i)

			server.devicesChanged.listen(listCb)

		startBootloader = (dev) ->
			device_conn = server.selectDevice(dev)
			cb = ->
				logDone()
				device_conn.changed.unListen(cb)
				if dev.model == 'com.nonolithlabs.bootloader'
					doUpdate()
				else
					log("Entering bootloader mode")
					server.send 'enterBootloader'
					waitForDevice serial, (i)->
						logDone()
						startBootloader(i)

					
			log("Selecting device")
			device_conn.changed.listen cb

		doUpdate = ->
			log("Validating image")

			product = device_conn.hw_product
			version = device_conn.hw_version

			if not (product == firmware.device and version == firmware.hwVersion)
				log('Firmware image is not for this hardware.', 'fail')
				log("Device: #{product} #{version}", 'fail')
				log("Firmware: #{firmware.device} #{firmware.hwVersion}", 'fail')
				if not params.nohwcheck then return
			else
				logDone()

			log("Erasing")
			device_conn.erase (m) ->
				logDone()
				log("Writing flash")
				device_conn.write firmware.data, (m) ->
					logDone()
					log("Verifying install")
					device_conn.crcApp (m) ->
						logDone()
						valid = (m.crc == firmware.crc)
						if not valid
							log("INVALID CRC #{m.crc} != #{firmware.crc}", 'fail')
						else
							log("Resetting device")
							device_conn.reset()
							waitForDevice serial, (i)->
								if i.model == 'com.nonolithlabs.bootloder'
									log("Device remained in bootloader mode", 'fail')
								else
									logDone()
									log("Success!", 'ok')
									$("#btn_done").show()
									track_feature('firmware-update-success')

		startBootloader(@device)
	
#URL params
params = {}
for param in document.location.search.slice(1).split('&')
	[k,v] = param.split('=')
	params[k]=v

console.log(params)

$(document).ready ->
	if not params.noga
		init_ga()

	app = new FirmwareUpdateApp(params)
