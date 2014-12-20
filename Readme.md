Nanika - Nanika
==========================

Nanika for Ikagaka

Installation
--------------------------

unstable

Usage
--------------------------

unstable

API
--------------------------

unstable

### constructor

    var nanika = new Nanika(nanikamanager, storage, namedmanager, ghostpath, profile, plugins={}, eventdefinitions={}, options={})

too much arguments?

### materialize()

    var promise = nanika.materialize()
    promise.then(function(){
      nanika.request('firstboot', {vanish_count: 0});
    });

start transaction and fire "materialize" event.

plugins should add event listeners on "materialize" events.

### request(event, request_args, callback, optionals)

    nanika.request('close');
    nanika.request('close', {reason: 'user'});
    nanika.request('name', null, function(args){console.log(args.value);});

request event and do response routine ("GET Sentence" and has value then play sakurascript) and callback(args, response).

### halt()

halt

Plugins
--------------------------

    NanikaPlugin.foo = {initialize: function(nanika){...}, destroy: function(nanika){...}};

see [NanikaDefaultPlugin](https://github.com/Ikagaka/NanikaDefaultPlugin)

Event Definitions
--------------------------

    NanikaEventDefinition.close = {
      method: 'GET', // default=GET
      submethod: 'Sentence', // default=Sentence
      id: 'OnClose', // required
      headers: {
        reason: 0
      }
    };

see [NanikaDefaultEventDefinition](https://github.com/Ikagaka/NanikaDefaultEventDefinition)

License
--------------------------

This is released under [MIT License](http://narazaka.net/license/MIT?2014).
