package ;

import js.Node;
import js.node.Connect;
import js.node.Express;
import js.node.FacebookClient;
import js.node.JsHelper;
import js.node.NodeUuid;
import js.node.SocketIo;

import SocketManager;

using js.node.JsHelper;
using Reflect;
using js.node.Express;

class Main {
	
	static function main() {
		runNode();
	}
	
	public static function runNode() {

		Node.paths.unshift(Node.__dirname + '/lib');
		var everyauth : EveryAuth = Node.require('everyauth');

		var express : Express  = Node.require('express');
	
		var facebook = new FacebookClient();

		var uuid : NodeUuid = Node.require('node-uuid');
		
		// configure facebook authentication
		everyauth.facebook
		  .appId(Node.process.env.FACEBOOK_APP_ID)
		  .appSecret(Node.process.env.FACEBOOK_SECRET)
		  .scope('user_likes,user_photos,user_photo_video_tags')
		  .entryPath('/')
		  .redirectPath('/home')
		  .findOrCreateUser(function() {
			return({});
		  });
		  

		var app = express.createServer(
		  express.logger(),
		  express.static_(Node.__dirname + '/public'),
		  express.cookieParser(),
		  // set this to a secret value to encrypt session cookies
		  express.session({ secret: 'secret123'.ifNull(Node.process.env.SESSION_SECRET) }),
		  // insert a middleware to set the facebook redirect hostname to http/https dynamically
		  function(request : ExpressHttpServerReq, response : ExpressHttpServerResp, next) {

			var method = 'http'.ifNull(request.headers.field('x-forwarded-proto'));

			everyauth.facebook.myHostname(method + '://' + request.headers.host);
			next();
		  },
		  everyauth.middleware(),
		  Node.require('facebook').Facebook()
		);
	
		// listen to the PORT given to us in the environment
		var port = 3000.ifNull(Node.process.env.PORT);

		app.listen(port, function() {
			trace('Listening on ' + port);
		});
		
		// create a socket.io backend for sending facebook graph data
		// to the browser as we receive it
		var socketIo : SocketIo = Node.require('socket.io');
		
		
		var io = socketIo.listen(app);

		// wrap socket.io with basic identification and message queueing
		// code is in lib/socket_manager.js
		var socket_managerB : SocketManagerBuilder = Node.require("socket_manager");
		var socket_manager = socket_managerB.create(io);
		
		// use xhr-polling as the transport for socket.io
		io.configure(function () {
		  io.set('transports', ['xhr-polling']);
		  io.set('polling duration', 10);
		});

		app.get("/pashome", function (req, resp) {
			
		});

		// respond to GET /home
		app.get('/home', function(request : ExpressHttpServerReq, response : ExpressHttpServerResp) {

		  // detect the http method uses so we can replicate it on redirects		  
		  var method =
			'http'.ifNull(request.field('x-forwarded-proto'));

		  // if we have facebook auth credentials
		  if (request.session.auth != null) {

			// initialize facebook-client with the access token to gain access
			// to helper methods for the REST api
			var token = request.session.auth.facebook.accessToken;
			facebook.getSessionByAccessToken(token)(function(session) {

			  // generate a uuid for socket association
			  var socket_id = uuid();

			  // query 4 friends and send them to the socket for this socket id
			  session.graphCall('/me/friends&limit=4')(function(result) {
				result.data.forEach(function(friend) {
				  socket_manager.send(socket_id, 'friend', friend);
				});
			  });

			  // query 16 photos and send them to the socket for this socket id
			  session.graphCall('/me/photos&limit=16')(function(result) {
				result.data.forEach(function(photo) {
				  socket_manager.send(socket_id, 'photo', photo);
				});
			  });
			  
			  // query 4 likes and send them to the socket for this socket id
			  session.graphCall('/me/likes&limit=4')(function(result) {
				result.data.forEach(function(like) {
				  socket_manager.send(socket_id, 'like', like);
				});
			  });

			  // use fql to get a list of my friends that are using this app
			  session.restCall('fql.query', {
				query: 'SELECT uid, name, is_app_user, pic_square FROM user WHERE uid in (SELECT uid2 FROM friend WHERE uid1 = me()) AND is_app_user = 1',
				format: 'json'
			  })(function(result) {
				result.forEach(function(friend) {
				  socket_manager.send(socket_id, 'friend_using_app', friend);
				});
			  });

			  // get information about the app itself
			  session.graphCall('/' + Node.process.env.FACEBOOK_APP_ID)(function(app) {
				// render the home page
				response.render('home.ejs', {
				  layout:   false,
				  token:    token,
				  app:      app,
				  user:     request.session.auth.facebook.user,
				  home:     method + '://' + request.headers.host + '/',
				  redirect: method + '://' + request.headers.host + request.url,
				  socket_id: socket_id
				});

			  });
			});

		  } else {

			// not authenticated, redirect to / for everyauth to begin authentication
			response.redirect('/');
		  }
		});
		
	}
}
