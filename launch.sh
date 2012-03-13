#!/bin/sh

case "$1" in
	local)
	   	APPURL="http://localhost:8000/pixelpulse.html"
		;;
	 
	edge)
		APPURL="http://apps.nonolithlabs.com/edge/pixelpulse"
		;;
	*)
		APPURL="http://apps.nonolithlabs.com/pixelpulse"
		;;
esac

CHROME=$(
       which chromium-browser \
	|| which google-chrome \
)

if [ -n "$CHROME" ]
then
	exec "$CHROME" --app="$APPURL"
else
	echo "Google Chrome is not installed or was not found"
fi
