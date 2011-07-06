import sys, pickle, getpass
import oauth1

services = []
AUTH_FILE = "auth.p"

if len(sys.argv) == 1:
	services = ["google"]
else:
	services = sys.argv[1:]
	
data = {}

for arg in services: 
	print "\n########################################################################"
	
	if arg == "google":
		data['google'] = {
			'CONSUMER_KEY': "anonymous",
			'CONSUMER_SECRET': "anonymous"
		}

		OAUTH_SETTINGS = {
		  'auth_params': {"scope": "https://spreadsheets.google.com/feeds/"},
		  'request_token_url':"https://www.google.com/accounts/OAuthGetRequestToken",
		  'authorize_url':'https://www.google.com/accounts/OAuthAuthorizeToken',
		  'access_token_url':'https://www.google.com/accounts/OAuthGetAccessToken',
		}
		oauth_token, oauth_token_secret = oauth1.get_token(OAUTH_SETTINGS,
			data['google']['CONSUMER_KEY'], data['google']['CONSUMER_SECRET'])
		
		data['google']['OAUTH_TOKEN'] = oauth_token
		data['google']['OAUTH_TOKEN_SECRET'] = oauth_token_secret
	
		raw_input("Hit enter to continue...")
		
	else:
		print "Unknown service " + arg
	
# write out all auth data
pickle.dump(data, open(AUTH_FILE, "wb"))
print "\nAuthorization data saved to " + AUTH_FILE

print "#################### You are all authorized! ###################"
