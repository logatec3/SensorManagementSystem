// HTTP server for SMS

var express = require('express');
var util = require('util');
var xutil = require('./xutil');
var fs = require('fs');
var path = require('path');
var session = require('express-session');
var MongoStore = require('connect-mongo')(session);
var bodyParser = require('body-parser');
var basicAuth = require('basic-auth-connect');
var favicon = require('serve-favicon');
var morgan = require('morgan');
var cookieParser = require('cookie-parser');
var http = require('http');
var io = require('socket.io');
var url = require('url');

///////////////////////////////////////////////////////////////////////////
// Module variables

var port = 3000;
var bl = null;
var db_url = null;
var db_syncer = null;
var scan_coordinator = null;

// cached pages

var help_content = null;
var login_content = null;
var root_content = null;

// optional middleware handlers
var body_parser = bodyParser.urlencoded({ extended: true });
var json_parser = bodyParser.json({ extended: true, limit: '10mb'});
var basic_auth = basicAuth(function (user, pass, callback) {
  bl.verify_user(user, pass, callback);
});

var static_file_handler2 = function (req, res, next) {
  var s = req.url.split("?");
  var fn = path.join(__dirname, '../public' + s[0]);

  var ext = path.extname(s[0]).toLowerCase();
  if (ext === ".html") {
    if (!req.session.is_authenticated) {
      return res.redirect("/login");
    }
  }
  if (fs.existsSync(fn)) {
    return res.sendFile(fn);
  }
  next();
}

////////////////////////////////////////////////////////////////////////////

function log_url(req, res, next) {
  console.log("[url]", req.url, req.method, (req.session ? req.session.is_authenticated : "unknown"));
  next();
};

function preprocess_api_calls(req, res, next) {
  if (req.url.toLowerCase().indexOf("/api") == 0) {
    // rest-like url parser
    var tmp_url = req.url;
    req.body = xutil.parse_rest_request(tmp_url);
    req.body.action = "rest";

    var source_ip = req.headers['x-forwarded-for'] || req.connection.remoteAddress.split(":").pop();

    if (source_ip == "127.0.0.1") {
      // trusted local access
      req.session.is_authenticated = true;
      req.session.user = "local";
      next();
    } else {
      // untrusted source ip
      // check token
      if(req.headers.authorization != null) {
        bl.get_users_token(req.headers.authorization, function(data) {
          if(data.error) res.status(data.status).json(data.error)
          else if (data[0] == null) res.status(401).json({ error: 'Specified token is not valid' });
          else {
            req.session.is_authenticated = true;
            req.session.user = data[0].username;
            next();
          }
        });
      } else {
        res.status(401).json("Error: Missing authentication token");
      }
    }
  } else if (req.url === "/handler" || req.url.indexOf("/handler?") === 0) {
    json_parser(req, res, next);
  } else {
    body_parser(req, res, next);
  }
};

function ensure_authenticated(req, res, next) {
  if (req.session.is_authenticated) { return next(); }
  res.redirect('/login');
}

function main_handler(req, res, next) {
  if (!req.body) return next(new Error("Unknown request body"));

  //console.log(req.body);
  var cmd = req.body;
  if (!cmd.action) return next(new Error("Unknown request - missing action"));

  cmd.session = { // attach user stuff
    user: req.session.user,
    ip: req.connection.remoteAddress
  };

  bl.new_login(cmd.session.user, cmd.session.ip, function (err) {
    if (err) return next(err);

    var action = cmd.action;
    if (action == "scan") {
      if (cmd.data && cmd.data.id) {
        scan_coordinator.scan(db_syncer, cmd.data.id, function () { });
      } else {
        scan_coordinator.scan(db_syncer, null, function () { });
      }
      res.end("{}"); // return immediatelly
    } else if (bl[action]) {
      // requests that map directly to exported function on BL are called here
      bl[action](cmd, function (err, result) {
        if (err) {
          var error_msg = err.message || err.err;
          var res_str = JSON.stringify({ error: { message: error_msg} }, null, "    ");
          //console.log(res_str);
          res.end(res_str);
          //res.end(JSON.stringify({ error: {message:error_msg} }, null, "    "));
        } else {
          var res_str = JSON.stringify(result, null, "    ");
          //console.log(res_str);
          res.end(res_str);
        }
      });
    } else {
      next(new Error("Unknown action"));
    }
  });
}

// main HTTP server function
function run() {

  var app = express();
  server = http.Server(app);
  io = io.listen(server);

  app.use(favicon("public/img/favicon.ico"));
  app.use(morgan('dev'));
  app.use(cookieParser());
  app.use(session({ secret: 'jcvsnasdovhjdsfanbdwkjv', saveUninitialized: true,
  resave: true, store: new MongoStore({ url: db_url , autoReconnect: true, safe: true}) }));
  app.use(log_url);
  app.use(static_file_handler2);
  app.use(preprocess_api_calls);
  app.use(json_parser);
  app.use(body_parser);

  // routes
  app.get('/', function (req, res) {
    res.setHeader("Content-Type", "text/html");
    res.end(root_content);
  });

  app.get('/login', function (req, res) {
    res.setHeader("Content-Type", "text/html");
    res.end(login_content);
  });

  app.post('/login', function (req, res, next) {
    bl.verify_user(req.body.username, req.body.password, function (err, user) {
      if (err) {
        bl.get_user({ data: { username: req.body.username} }, function (err, data) {
          var msg = "";
          if (err) {
            msg = "Login failed";
          } else {
            msg = "User cannot login - wrong password or user inactive.";
          }
          res.redirect('/login?msg=' + encodeURI(msg));
        });
      } else {
        req.session.is_authenticated = true
        req.session.user = user;
        res.redirect('/admin.html');
      }
    });
  });

  app.get('/logout', function (req, res) {
    req.session.destroy();
    res.redirect('/login');
  });

  app.get('/help', function (req, res) {
    res.setHeader("Content-Type", "text/html");
    res.end(help_content);
  });
  app.post('/handler', ensure_authenticated, main_handler);

  app.route('/api')
  .get(function(req, res) {
    var response = {
      "collections": [
        {
          "name": "nodes",
          "href": "/nodes"
        },
        {
          "name": "clusters",
          "href": "/clusters"
        },
        {
          "name": "sensors",
          "href": "/sensors"
        },
        {
          "name": "measurements",
          "href": "/measurements"
        }
      ]
    }
    res.json(response);
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET').json( req.method + ' method is not supported.' );
  });

  app.route('/api/measurements')
  .get(function(req, res) {
    bl.get_all_measurements(req, function(callback) {
      if (callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    });
  })
  .post(function(req, res) {
    if (!req.body.ts) {
      req.body.ts = new Date();
    }
    io.emit('measurements', req.body);
    bl.api_add_sensor_measurement(req.body, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.status(callback.status).json(callback.message);
    });
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,POST').json( req.method + ' method is not supported.' );
  });
  app.route('/api/measurements/:measurement_id')
  .get(function(req, res) {
    bl.get_sensor_measurement(req.params.measurement_id, function(callback) {
      if (callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    })
  })
  .put(function(req, res) {
    bl.update_sensor_measurement(req, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .delete(function(req, res) {
    bl.delete_sensor_measurement(req.params.measurement_id, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,PUT,DELETE').json( req.method + ' method is not supported.' );
  });
  app.route('/api/nodes')
  .get(function(req, res) {
    bl.api_get_nodes(req, function(callback) {
      if (callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    });
  })
  .post(function(req, res) {
    bl.api_add_node(req.body, function(callback) {
      if(callback.error) res.json(callback.error).status(callback.status);
      else res.json(callback.message).status(callback.status);
    })
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,POST').json( req.method + ' method is not supported.' );
  });
  app.route('/api/nodes/:node_id')
  .get(function(req, res) {
    bl.api_get_node(req.params.node_id, function (callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    })
  })
  .put(function(req, res) {
    bl.api_update_node(req, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .delete(function(req, res) {
    bl.api_delete_node(req.params.node_id, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,PUT,DELETE').json( req.method + ' method is not supported.' );
  });
  app.route('/api/clusters')
  .get(function(req, res) {
    bl.api_get_clusters(req, function (err, clusters) {
      if (err) return res.json(err);
      res.json(clusters);
    });
  })
  .post(function(req, res) {
    bl.api_add_cluster(req.body, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.status(callback.status).json(callback.message);
    });
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,POST').json( req.method + ' method is not supported.' );
  });
  app.route('/api/clusters/:cluster_id')
  .get(function(req, res) {
    bl.api_get_cluster(req.params.cluster_id, function (callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    })
  })
  .put(function(req, res) {
    bl.api_update_cluster(req, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .delete(function(req, res) {
    bl.api_delete_cluster(req.params.cluster_id, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,PUT,DELETE').json( req.method + ' method is not supported.' );
  });
  app.route('/api/sensors')
  .get(function(req, res) {
    bl.get_sensors(req, function (callback) {
      if (callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    });
  })
  .post(function(req, res) {
    bl.add_sensor(req.body, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.status(callback.status).json(callback.message)
    });
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,POST').json( req.method + ' method is not supported.' );
  });
  app.route('/api/sensors/:sensor_id')
  .get(function(req, res) {
    bl.get_sensor(req.params.sensor_id, function(callback) {
      if (callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback);
    })
  })
  .put(function(req, res) {
    bl.update_sensor(req, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .delete(function(req, res) {
    bl.delete_sensor(req.params.sensor_id, function(callback) {
      if(callback.error) res.status(callback.status).json(callback.error);
      else res.json(callback.message);
    })
  })
  .all(function(req, res) {
    res.status(405).header('Access-Control-Allow-Methods', 'GET,PUT,DELETE').json( req.method + ' method is not supported.' );
  });
  app.get('/api/*', main_handler);
  app.post('/api/*', main_handler);

    app.use(function(err, req, res, next) {
      res.status(404).json("The requested resource could not be found!");
    });

    // ok, start the server
    server.listen(port, function() {
      console.log("Running HTTP server on port " + port);
    });
}

  ///////////////////////////////////////////////////////////////////////////////////

  function init(options, callback) {
    bl = options.bl;
    if (options.web.port) {
      port = options.web.port;
    }
    if (options.database && options.database.url) {
      db_url = options.database.url;
    }
    scan_coordinator = options.scan_coordinator;
    db_syncer = options.db_syncer;

    //prepare help file
    //console.log("Caching help file...");
    //var md_content = fs.readFileSync("docs/docs.md") + "";
    //var html_frame = fs.readFileSync("public/help.htmlx") + "";
    //var md_parser = require("marked");
    //help_content = html_frame.replace("${main_content}", md_parser(md_content));

    // PRODUCES ERROR:
    // /root/SensorManagementSystem/node_modules/mongodb/lib/utils.js:123
    // process.nextTick(function() { throw err; });
    //                               ^
    // TypeError: md_parser is not a function
    // at Object.init (/root/SensorManagementSystem/app/server.js:426:58)
    // at /root/SensorManagementSystem/app.js:62:25

    // prepare login file
    console.log("Caching login page...");
    login_content = fs.readFileSync("public/login.html");

    // prepare root file
    console.log("Caching root page...");
    root_content = fs.readFileSync("public/index.html");

    callback();
  }

  //////////////////////////////////////////////////////////////////

  exports.init = init;
  exports.run = run;
