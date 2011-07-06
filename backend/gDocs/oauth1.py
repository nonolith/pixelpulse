#!/usr/bin/python

""" OAuth Login.

Uses python-oauth2 library to perform 3-way handshake.
Note this does NOT import metapy.auth.oauth2, which is for OAuth 2.0.

1. Create a new instance OAuth
2. Call the generateAuthorizationURL method to create
the authorization URL
3. Once the user grants access
4. Call the authorize method to upgrade to an access
token.
"""

from __future__ import absolute_import
import urlparse, webbrowser, pickle, oauth2
from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer

class OAuthHTTPHandler(BaseHTTPRequestHandler):
	response = None
	
	def do_GET(self):
		response = urlparse.urlparse(self.path).query
		self.send_response(200)
		self.send_header('Content-type','text/html')
		self.end_headers()
		self.wfile.write("<h1>OAuth Verified. <span style='color:#0f0'>You can now close this browser window.</span></h1>" + response)
		
		OAuthHTTPHandler.response = response
		return

class OAuth():

	def generate_auth_url(self, OAUTH_SETTINGS, consumer_key, consumer_secret, domain, callback_url):
		""" Fetch the OAuthToken and generate the authorization URL.
		Returns:
			the Authorization URL
		"""

		consumer = oauth2.Consumer(consumer_key, consumer_secret)
		client = oauth2.Client(consumer)

		req = oauth2.Request(method="GET", url=OAUTH_SETTINGS['request_token_url'], \
			parameters=dict({"oauth_callback": "http://localhost:8080"}, **OAUTH_SETTINGS['auth_params']))
		signature_method = oauth2.SignatureMethod_HMAC_SHA1()
		#req.sign_request(signature_method, consumer, None)
		resp, content = client.request(req.to_url(), "GET")
		if resp['status'] != '200':
			raise Exception("Invalid response %s." % resp['status'])

		query = urlparse.parse_qs(content)
		auth_url = "%s?oauth_token=%s&&domain=%s" % (OAUTH_SETTINGS['authorize_url'],
			query['oauth_token'][0],
			domain)
		return auth_url, query['oauth_token'][0], query['oauth_token_secret'][0]
		
	def verify_token(self, auth_url):
		""" User-verifies token with webbrowser
		Returns:oauth_token_secret
			the verifier token
		"""
		webbrowser.open(auth_url)
		
		server = HTTPServer(('', 8080), OAuthHTTPHandler)
		print "!!! WAIT FOR THE VERIFICATION PAGE TO OPEN IN YOUR FAVORITE WEBBROWSER!"
		print ""
		print "Started response server at http://localhost:8080/..."
		while not OAuthHTTPHandler.response:
			server.handle_request()
		print "Server closed."
		print ""
		
		query = urlparse.parse_qs(OAuthHTTPHandler.response)
		OAuthHTTPHandler.response = None
		return query['oauth_verifier'][0]

	def authorize(self, OAUTH_SETTINGS, consumer_key, consumer_secret, oauth_token, oauth_token_secret, oauth_verifier):
		""" Upgrade OAuth to Access Token
		Returns:
			the oauth token
			the token secret
		"""
		consumer = oauth2.Consumer(consumer_key, consumer_secret)
		token = oauth2.Token(oauth_token, oauth_token_secret)
		client = oauth2.Client(consumer, token)

		req = oauth2.Request(method="GET", url=OAUTH_SETTINGS['access_token_url'], parameters={"oauth_verifier": oauth_verifier})
		resp, content = client.request(req.to_url(), "GET")
		if resp['status'] != "200":
			raise Exception(content)

		query = urlparse.parse_qs(content)
		return query['oauth_token'][0], query['oauth_token_secret'][0]

def get_token(OAUTH_SETTINGS, consumer_key, consumer_secret):
	""" Runs authorization process
	Returns:
		the oauth token
		the token secret
	"""
	o = OAuth()
	auth_url, oauth_token, oauth_token_secret = o.generate_auth_url(OAUTH_SETTINGS, consumer_key, consumer_secret, "http://localhost:8080", "http://localhost:8080")
	oauth_verifier = o.verify_token(auth_url)
	oauth_token, oauth_token_secret = o.authorize(OAUTH_SETTINGS, consumer_key, consumer_secret, oauth_token, oauth_token_secret, oauth_verifier)
	print "OAuth Token: %s\nOAuth Secret: %s\n" % (oauth_token, oauth_token_secret)
	return oauth_token, oauth_token_secret
