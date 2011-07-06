#!/usr/bin/python2.6
import os.path, sys
import json
import urllib2
import urllib
import urlparse
import BaseHTTPServer
import webbrowser

def get_url(path, args=None):
    args = args or {}
    if 'access_token' in args or 'client_secret' in args:
        endpoint = "https://"+ENDPOINT
    else:
        endpoint = "http://"+ENDPOINT
    return endpoint+path+'?'+urllib.urlencode(args)

def get(path, args=None):
    return urllib2.urlopen(get_url(path, args=args)).read()

class RequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
	def do_GET(self):
		global ACCESS_TOKEN, APP_ID, APP_SECRET

		self.send_response(200)
		self.send_header("Content-type", "text/html")
		self.end_headers()
		
		if urlparse.urlparse(self.path).path != '/':
			return

		code = urlparse.parse_qs(urlparse.urlparse(self.path).query).get('code')
		code = code[0] if code else None
		if code is None:
			self.wfile.write("Sorry, authentication failed.")
			sys.exit(1)
		response = get('/oauth/access_token', {'client_id':APP_ID,
											   'redirect_uri': 'http://localhost:8080/',
											   'client_secret':APP_SECRET,
											   'code':code})
		ACCESS_TOKEN = urlparse.parse_qs(response)['access_token'][0]
		
		self.wfile.write("You have successfully logged in to facebook. "
						 "You can close this window now.")
						 
ACCESS_TOKEN = None
						 
def get_token(settings, key, secret):
	global ACCESS_TOKEN, APP_ID, APP_SECRET, ENDPOINT
	APP_ID = key
	APP_SECRET = secret
	ENDPOINT = settings['endpoint']
	
	print "Logging you in to facebook..."
	print dict({'client_id':APP_ID,
							 'redirect_uri':'http://localhost:8080/'}, **settings)
	webbrowser.open(get_url('/oauth/authorize',
							dict({'client_id':APP_ID,
							 'redirect_uri':'http://localhost:8080/'}, **settings['auth_params'])))

	httpd = BaseHTTPServer.HTTPServer(('127.0.0.1', 8080), RequestHandler)
	while ACCESS_TOKEN is None:
		httpd.handle_request()

	return ACCESS_TOKEN
