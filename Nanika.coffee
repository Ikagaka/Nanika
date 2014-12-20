Promise = @Promise
SakuraScriptPlayer = @SakuraScriptPlayer
NanikaDirectory = @NanikaDirectory
EventEmitter = @EventEmitter2

class Nanika extends EventEmitter
	constructor: (@nanikamanager, @storage, @namedmanager, @ghostpath, @profile, @plugins={}, @eventdefinitions={}, @options={}) ->
		@setMaxListeners(0)
		@charset = 'UTF-8'
		@sender = 'Ikagaka'
		@state = 'init' # init -> running <-> pending -> halted
	log: (message) ->
		console.log(message)
	warn: (message) ->
		console.warn(message)
	error: (err) ->
		console.error(err.stack)
	throw: (err) ->
		alert?(err)
		throw err
	load_ghost: ->
		@log "initializing ghost"
		ghost = new Ghost("/ghost/#{@ghostpath}/ghost/master/", @storage.ghost_master(@ghostpath).asArrayBuffer(), @options.append_path)
		ghost.logging = @options.logging
		ghost.push()
		.then ->
			ghost.load()
		.then =>
			@log "ghost loaded"
			ghost
	load_shell: (shellpath) ->
		@log "initializing shell"
		shell = new Shell(@storage.shell(@ghostpath, shellpath).asArrayBuffer())
		shell.load()
		.then =>
			@log "shell loaded"
			@profile.profile.shellpath = shellpath
			shell
	load_balloon: (balloonpath) ->
		@log "initializing balloon"
		balloon = new Balloon(@storage.balloon(balloonpath).asArrayBuffer())
		balloon.load()
		.then =>
			@log "balloon loaded"
			@profile.profile.balloonpath = balloonpath
			balloon
	materialize: ->
		shellpath = @profile.profile.shellpath || 'master'
		balloonpath = @profile.profile.balloonpath || @nanikamanager.profile.profile.balloonpath
		Promise.all [@load_ghost(), @materialize_named(shellpath, balloonpath)]
		.then ([ghost]) =>
			new Promise (resolve, reject) =>
				@ghost = ghost
				@resource = {}
				@protocol_version = '2.6'
				@transaction = new Promise (resolve) -> resolve()
				@initialize_plugins()
				@state = 'running'
				@log "materialized"
				@on 'version.set', =>
					resolve()
				@emit 'materialized'
				@named.load()
		.catch @throw
	initialize_plugins: ->
		for name, {initialize} of @plugins
			if initialize? then initialize(@)
	destroy_plugins: ->
		for name, {destroy} of @plugins
			if destroy? then destroy(@)
	add_plugin: (name, plugin) ->
		if @plugins[name]?
			throw new Error "plugin [#{name}] is already installed"
		@plugins[name] = plugin
		if @state == 'running'and plugin.initialize?
			plugin.initialize(@)
	remove_plugin: (name) ->
		unless @plugins[name]?
			throw new Error "plugin [#{name}] is not installed"
		plugin = @plugins[name]
		if plugin.destroy? then plugin.destroy(@)
		delete @plugins[name]
	request: (event, request_args, callback, optionals) ->
		method = null
		submethod = null
		event_definition = @eventdefinitions[event]
		@transaction = @transaction
		.then =>
			unless event_definition?
				throw new Error "event definition of [#{event}] not found"
			if @state != 'running'
				if event_definition.drop_when_not_running
					return
			request_definition = event_definition.request
			if request_definition instanceof Function
				{method, submethod, id, headers} = request_definition(@, request_args, optionals)
				method ?= 'GET'
			else if request_definition instanceof Object
				headers_definition = request_definition.headers
				if headers_definition instanceof Function
					headers = headers_definition(@, request_args, optionals)
				else if headers_definition instanceof Object and request_args?
					headers = {}
					for name, value of request_args
						header_definition = headers_definition[name]
						if typeof header_definition == 'string' or header_definition instanceof String or typeof header_definition == 'number' or header_definition instanceof Number
							if value?
								header_name = if not isNaN(header_definition) then "Reference#{header_definition}" else header_definition
								headers[header_name] = value
						else if header_definition instanceof Object
							unless header_definition.name?
								throw new Error "event definition of [#{event}] has no header name [#{name}] header definition"
							if header_definition.value instanceof Function
								value = header_definition.value(value, @, request_args, optionals)
							else if header_definition.value?
								throw new Error "event definition of [#{event}] has invalid [#{name}] header definition"
							if value?
								header_name = if not isNaN(header_definition.name) then "Reference#{header_definition.name}" else header_definition.name
								headers[header_name] = value
						else if header_definition?
							throw new Error "event definition of [#{event}] has invalid [#{name}] header definition"
				else if headers_definition?
					throw new Error "event definition of [#{event}] has no valid request header definition"
				method = request_definition.method || 'GET'
				submethod = request_definition.submethod
				id = request_definition.id
				unless id?
					throw new Error "event definition of [#{event}] has no id"
			else
				throw new Error "event definition of [#{event}] has no valid request definition"
			@emit "request.#{event}", request_args, optionals
			@send_request [method, submethod], @protocol_version, id, headers
		.then (response) =>
			unless response?
				return
			response_definition = event_definition.response
			if response_definition?.args
				response_args = response_definition.args(@, response)
			else
				if response.status_line.version == '3.0'
					value_name = 'Value'
				else
					if submethod == 'String'
						value_name = 'String'
					else if submethod == 'Word'
						value_name = 'Word'
					else if submethod == 'Status'
						value_name = 'Status'
					else
						value_name = 'Sentence'
				response_args = {}
				if response.headers.header[value_name]?
					response_args.value = response.headers.header[value_name]
				for name, value of response.headers.header
					unless name == value_name
						response_args[name] = value
			@emit "response.#{event}", response_args, optionals
			if method == 'GET' and (not submethod? or submethod == 'Sentence')
				if response_args.value? and (typeof response_args.value == "string" or response_args.value instanceof String)
					@ssp.play response_args.value, 'finish': => @emit "ssp.finish.#{event}", response_args, optionals
			if callback?
				callback(response_args, response)
			return
		.catch @error
	send_request: (method, version, id, headers={}) ->
		###
		SHIORI/2.x互換変換
		- GET : Sentence : OnCommunicate はGET Sentence SHIORI/2.3に変換され、ヘッダの位置が変更されます。
		- GET : TEACH : OnTeach はTEACH SHIORI/2.4に変換され、ヘッダの位置が変更されます。
		###
		new Promise (resolve, reject) =>
			request = new ShioriJK.Message.Request()
			request.request_line.protocol = "SHIORI"
			request.request_line.version = version
			request.headers.header["Sender"] = @sender
			request.headers.header["Charset"] = @charset
			if version == '3.0'
				request.request_line.method = method[0]
				request.headers.header["ID"] = id
			else
				if method[1] == null
					resolve() # through no SHIORI/2.x event
				method[1] ?= 'Sentence' # default SHIORI/2.2
				unless method[1] == 'TEACH'
					request.request_line.method = method[0] + ' ' + method[1]
				else
					request.request_line.method = method[1]
				if method[1] == 'Sentence' and id?
					if id == "OnCommunicate" # SHIORI/2.3b
						request.headers.header["Sender"] = headers["Reference0"]
						request.headers.header["Sentence"] = headers["Reference1"]
						request.headers.header["Age"] = "0" # temporary
						for key, value of headers
							if result = key.match(/^Reference(\d+)$/)
								request.headers.header["Reference"+(result[1]-2)] = ''+value
							else
								request.headers.header[key] = ''+value
						headers = null
					else # SHIORI/2.2
						headers["Event"] = id
				else if method[1] == 'String' and id? # SHIORI/2.5
					headers["ID"] = id
				else if method[1] == 'TEACH' # SHIORI/2.4
					request.headers.header["Word"] = headers["Reference0"]
					for key, value of headers
						if result = key.match(/^Reference(\d+)$/)
							request.headers.header["Reference"+(result[1]-1)] = ''+value
						else
							request.headers.header[key] = ''+value
					headers = null
				else if method[1] == 'OwnerGhostName' # SHIORI/2.0 NOTIFY
					request.headers.header["Ghost"] = headers["Reference0"]
					headers = null
				else if method[1] == 'OtherGhostName' # SHIORI/2.3 NOTIFY
					ghosts = []
					for key, value of headers
						if key.match(/^Reference\d+$/)
							ghosts.push ''+value
						else
							request.headers.header[key] = ''+value
					ghosts_headers = (ghosts.map (ghost) -> "GhostEx: #{ghost}\r\n").join("")
					request = request.request_line + "\r\n" + request.headers + ghosts_headers + "\r\n"
					headers = null
			if headers?
				for key, value of headers
					request.headers.header[key] = ''+value
			@emit "request_raw.#{id}", request
			@ghost.request ""+request
			.then (response) ->
				resolve(response)
			.catch (err) ->
				reject(err)
		.catch @throw
		.then (response_str) =>
			unless response_str? then return
			unless /\r\n\r\n$/.test(response_str)
				@warn "SHIORI Response does not end with termination string (CRLFCRLF)\n[#{response_str}]\nreplace CRLF end to CRLFCRLF"
				response_str = response_str.replace /\r\n(?:\r\n)?$/, '\r\n\r\n'
			parser = new ShioriJK.Shiori.Response.Parser()
			try
				response = parser.parse(response_str)
			catch
				@warn "SHIORI Response is invalid\n[#{response_str}]"
				return
			@emit "response_raw.#{id}", response
			if response.headers.header.Charset? then @charset = response.headers.header.Charset
			response
	halt: ->
		if @state == 'halted'
			return
		@emit 'halt'
		@state = 'halted'
		@transaction = null
		@vanish_named()
		@ghost.unload()
		.then =>
			@ghost.pull()
		.then (directory) =>
			@storage.ghost_master(@ghostpath, new NanikaDirectory(directory))
			@emit 'halted'
			@removeAllListeners()
		return
	change_named: (shellpath, balloonpath) ->
		if @named?
			@vanish_named()
		@materialize_named(shellpath, balloonpath)
	materialize_named: (shellpath, balloonpath) ->
		Promise.all [@load_shell(shellpath), @load_balloon(balloonpath)]
		.then ([shell, balloon]) =>
			@namedid = @namedmanager.materialize(shell, balloon)
			@named = @namedmanager.named(@namedid)
			@ssp = new SakuraScriptPlayer(@named)
			return
	vanish_named: ->
		if @ssp?
			@ssp.off()
			delete @ssp
		if @namedid?
			@namedmanager.vanish(@namedid)
			delete @named
			delete @namedid

if module?.exports?
	module.exports = Nanika
else if @Ikagaka?
	@Ikagaka.Nanika = Nanika
else
	@Nanika = Nanika
