{CarrierFactory} = require '../helpers/carrier'
shipper = require '../helpers/shipper'
guessCarrier = shipper.guessCarrier
https = require 'https'
noErr = null
_carrierFactory = new CarrierFactory()

tokenCache = { token: null, expires: 0 }

httpsPost = (hostname, path, headers, body, callback) ->
  data = JSON.stringify body
  options =
    hostname: hostname
    path: path
    method: 'POST'
    headers: Object.assign {}, headers,
      'Content-Length': Buffer.byteLength data
  req = https.request options, (res) ->
    chunks = []
    res.on 'data', (chunk) -> chunks.push chunk
    res.on 'end', ->
      try
        callback null, JSON.parse Buffer.concat(chunks).toString()
      catch e
        callback 'Failed to parse response'
  req.on 'error', (e) -> callback e.message
  req.write data
  req.end()

getAccessToken = (callback) ->
  now = Date.now()
  if tokenCache.token and tokenCache.expires > now
    return callback null, tokenCache.token
  clientId = process.env.USPS_CLIENT_ID
  clientSecret = process.env.USPS_CLIENT_SECRET
  return callback('Missing USPS_CLIENT_ID or USPS_CLIENT_SECRET') unless clientId and clientSecret
  body =
    grant_type: 'client_credentials'
    client_id: clientId
    client_secret: clientSecret
  httpsPost 'apis.usps.com', '/oauth2/v3/token', {'Content-Type': 'application/json'}, body, (err, data) ->
    return callback(err) if err
    if data.access_token
      tokenCache.token = data.access_token
      tokenCache.expires = now + (data.expires_in * 1000) - 60000
      callback null, data.access_token
    else
      callback data.error_description or data.error or 'Token failed'

trackUSPS = (trackingNumber, callback) ->
  getAccessToken (err, accessToken) ->
    return callback(err) if err
    headers =
      'Authorization': "Bearer #{accessToken}"
      'Content-Type': 'application/json'
    httpsPost 'apis.usps.com', '/tracking', headers, [{trackingNumber: trackingNumber}], (err, data) ->
      return callback(err) if err
      callback null, data

module.exports =
  show: (req, res) ->
    carrierClient = _carrierFactory.getCarrier req.params.carrier
    return res.status(404).send error: 'carrier not supported' unless carrierClient?
    if req.params.carrier is 'usps'
      trackUSPS req.params.trackingNumber, (err, data) ->
        if err
          res.status(200).set('Content-Type', 'application/json').send {error: err}
        else
          res.status(200).set('Content-Type', 'application/json').send data
      return
    requestOptions = _carrierFactory.getRequestOptions req.params
    carrierClient.requestData requestOptions, (err, resp) ->
      data = {error: err or 'unknown error'} if err? or !resp?
      data = data or resp
      res.status(200)
        .set('Content-Type', 'application/json')
        .send data

  guess: (req, res) ->
    res.status(200)
      .set('Content-Type', 'application/json')
      .send guessCarrier req.params.trackingNumber
