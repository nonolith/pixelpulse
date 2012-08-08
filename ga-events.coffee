
window.init_ga = ->
	window._gaq = window._gaq || [];
	_gaq.push(['_setAccount', 'UA-22566654-2']);
	_gaq.push(['_trackPageview']);

	ga = document.createElement('script')
	ga.type = 'text/javascript'
	ga.async = true;
	ga.src = (if 'https:' == document.location.protocol then 'https://ssl' else 'http://www') + '.google-analytics.com/ga.js'
	s = document.getElementsByTagName('script')[0]
	s.parentNode.insertBefore(ga, s)

	_gaq.push -> console.log("GA ran")

window.ga_event = ga_event = (category, event, data, value) ->
	_gaq.push(['_trackEvent', category, event, data, value])

feature_events = []

window.track_feature = track_feature = (feature) ->
	if feature not in feature_events
		feature_events.push(feature)
		ga_event("feature", feature)
		console.log("tracking feature", feature)
	else
		console.log("already tracked", feature)

