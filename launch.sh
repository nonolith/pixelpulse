#!/bin/sh
DIR="$( cd "$( dirname "$0" )" && pwd )"
APPURL="file://$DIR/index.html"

CHROME=$(
       which chromium-browser \
	|| which google-chrome \
	|| (test -d "/Applications/Google Chrome.app/" && echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") \
)

if [ -n "$CHROME" ]
then
	exec "$CHROME" --app="$APPURL"
else
	echo "Google Chrome is not installed or was not found"
fi
