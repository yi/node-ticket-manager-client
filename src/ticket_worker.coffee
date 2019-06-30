
assert = require "assert"
_ = require "lodash"
oauth = require "./utils/oauth"

env = process.env.NODE_ENV || 'development'
DEFAULT_BASIC_AUTH = require('./config/config')[env]['basicAuth']

debuglog = require("debug")("ticketman:TicketWorker#")

{EventEmitter} = require('events')
request = require "request"

PATH_FOR_REQUIRE_TICKET = "/api/tickets/assign"

# job timeout setting
DEFAULT_TIMEOUT = 20*60*1000

# interval for watching
DEFAULT_WATCH_INTERVAL = 1000

# @event "new ticket", ticket
# @event "timeout", ticket
class TicketWorker extends EventEmitter

  # @param {Object} options, optionally includes:
  #     options.name
  #     options.id
  #     options.consumerSecret
  #     options.host
  #     options.category
  #     options.timeout : ticket processing timeout in ms
  #     options.interval : self checking interval
  #     options.basicAuth : basicAuth
  #
  constructor: (options={}) ->
    super(options)

    console.dir options
    #@name = options.name
    @id = options.id
    @consumerSecret = options.consumer_secret || options.consumerSecret
    @watchCategory = options.category
    @host = options.host

    #assert @name, "missing name"
    assert @id, "missing id"
    assert @consumerSecret, "missing consumer secret"
    assert @watchCategory, "missing category to watch"
    assert @host, "missing host"

    @oauth =
      consumer_key: @id
      consumer_secret: @consumerSecret

    @_isBusy = false
    @timeout = options.timeout || DEFAULT_TIMEOUT
    @interval = options.interval || DEFAULT_WATCH_INTERVAL
    @basicAuth = options.basicAuth || DEFAULT_BASIC_AUTH

    if @timeout < @interval * 3 then @timeout = @interval * 3

    @ticket = null
    @commenceAt = 0

    debuglog "constructor,  @watchCategory:#{@watchCategory}, @timeout:#{@timeout}, @interval:#{@interval}"
    setInterval (()=>@watch()), @interval

    debuglog "[TicketWorker:constructor] @:%j", @

  isBusy : -> @_isBusy

  watch : ->
    debuglog "watch: isBusy:#{@isBusy()}"
    if @isBusy()
      @giveup("ticket timeout") if Date.now() > @timeout +  @commenceAt
      #@doTimeout() if Date.now() > @timeout +  @commenceAt
    else
      @requireTicket()
    return

  setBusy : (val)->
    debuglog "setBusy val:#{val}"
    @_isBusy = Boolean(val)
    @commenceAt = Date.now() if @_isBusy

  # require a new ticket from server
  requireTicket : ()->
    debuglog "requireTicket"
    return if @isBusy()

    @setBusy(true) # mark  i'm busy

    body = category : @watchCategory

    options =
      method: 'PUT'
      auth : @basicAuth
      url: "#{@host}#{PATH_FOR_REQUIRE_TICKET}"
      headers : oauth.makeSignatureHeader(@id, 'PUT', PATH_FOR_REQUIRE_TICKET, body, @consumerSecret)
      json : body

    request options, (err, res, data)=>
      ticket = data.result || {}
      debuglog "requireTicket: err:#{err}, res.statusCode:#{if res? then res.statusCode else "n/a"}, ticket:%j", (if data.success then "#{ticket.title}(#{ticket.id})" else data.message)

      if err? then return debuglog "requireTicket: err: #{err}"

      unless res.statusCode is 200 then return debuglog "requireTicket: request failed, server status: #{res.statusCode}"

      unless data.success?
        @setBusy(false)
        debuglog "requireTicket: request failed, #{data.message}"
        return

      console.dir ticket
      if _.isEmpty(ticket)
        @setBusy(false)
        debuglog "requireTicket: no more ticket"
        return

      @ticket = ticket
      #@ticket.id = @ticket._id if @ticket._id
      try
        @ticket.content = JSON.parse(ticket.content)
      catch err
        debuglog "ticket.content not json "
      @emit "new ticket", @ticket
      return
    return

  # when timeout
  #doTimeout : ->
    #debuglog "doTimeout, @ticket:%j", @ticket
    #@giveup("ticket timeout")
    #_ticket = @ticket
    #@ticket = null
    #@emit "timeout", _ticket
    #@setBusy(false)
    #return

  # complete ticket
  complete : ()->
    return unless @isBusy()

    path = "/api/tickets/#{@ticket.id}/complete"
    options =
      method: 'PUT'
      auth : @basicAuth
      headers : oauth.makeSignatureHeader(@id, 'PUT', path, {}, @consumerSecret)
      json : {}
      url: "#{@host}#{path}"
    console.dir options
    request options, (err, res, data)=>
      ticket = data.result||{}
      debuglog "complete: err:#{err}, res.statusCode:#{if res? then res.statusCode else "n/a"}, ticket:%j", (if data.success then "#{ticket.title}(#{ticket.id})" else data.message)
      #return

      _ticket = @ticket
      @ticket = null
      @emit "complete", _ticket
      @setBusy(false)
      return

  # send comment on to current ticket
  update : (message, kind='default')->
    return debuglog "update: ERROR: current has no ticket. message:#{message}" unless @ticket?

    body =
      #kind : kind
      comment : message

    path = "/api/tickets/#{@ticket.id}/comment"

    options =
      method: 'PUT'
      auth : @basicAuth
      headers : oauth.makeSignatureHeader(@id, 'PUT', path, body, @consumerSecret)
      url: "#{@host}#{path}"
      json : body
    console.dir options
    request options, (err, res, data)->
      ticket = data.result||{}
      debuglog "update: err:#{err}, res.statusCode:#{if res? then res.statusCode else "n/a"}, ticket:%j", (if data.success then "#{ticket.title}(#{ticket.id})" else data.message)
      return
    return

  # give up the current ticket
  giveup: (reason)->
    debuglog "giveup"

    return unless @isBusy()

    unless @ticket?
      debuglog "ERROR: busy but not ticket!!!!"
      @setBusy false
      return

    path = "/api/tickets/#{@ticket.id}/giveup"

    body =
      reason : reason

    options =
      method: 'PUT'
      auth : @basicAuth
      headers : oauth.makeSignatureHeader(@id, 'PUT', path, body, @consumerSecret)
      url: "#{@host}#{path}"
      json : body
    console.dir options
    request options, (err, res, data)=>
      ticket = data.result||{}
      debuglog "giveup: err:#{err}, res.statusCode:#{if res? then res.statusCode else "n/a"}, ticket:%j", (if data.success then "#{ticket.title}(#{ticket.id})" else data.message)
      _ticket = @ticket
      @ticket = null
      @emit "giveup", _ticket
      @setBusy(false)
      return

    return

module.exports=TicketWorker

