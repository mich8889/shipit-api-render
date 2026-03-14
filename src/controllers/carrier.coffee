{CarrierFactory} = require '../helpers/carrier'
shipper = require '../helpers/shipper'
guessCarrier = shipper.guessCarrier
noErr = null
_carrierFactory = new CarrierFactory()

# === NEW USPS v3 HELPER (OAuth token + Tracking) ===
tokenCache = { token: null, expires: 0 }

getAccessToken = (callback) ->
  now = Date.now()
  if tokenCache.token and tokenCache.expires > now
    return callback null, tokenCache.token

  clientId = process.env.USPS_CLIENT_ID
  clientSecret = process.env.USPS_CLIENT_SECRET
  return callback('Missing USPS_CLIENT_ID or USPS_CLIENT_SECRET') unless clientId and clientSecret

  fetch 'https://apis.usps.com/oauth2/v3/token',
    method: 'POST'
    headers: 'Content-Type': 'application/json'
    body: JSON.stringify
      grant_type: 'client_credentials'
      client_id: clientId
      client_secret: clientSecret
  .then (response) -> response.json()
  .then (data) ->
    if data.access_token
      tokenCache.token = data.access_token
      tokenCache.expires = now + (data.expires_in * 1000) - 60000
      callback null, data.access_token
    else
      callback data.error_description or data.error or 'Token failed'
  .catch (err) -> callback err.message or err

trackUSPS = (trackingNumber, callback) ->
  getAccessToken (err, accessToken) ->
    return callback(err) if err

    fetch 'https://apis.usps.com/tracking',
      method: 'POST'
      headers:
        'Authorization': "Bearer #{accessToken}"
        'Content-Type': 'application/json'
      body: JSON.stringify([{ trackingNumber: trackingNumber }])
    .then (response) ->
      if !response.ok then throw new Error("HTTP #{response.status}")
      response.json()
    .then (body) -> callback null, body
    .catch (err) -> callback err.message or err

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
```

**To deploy:**
1. Go to `https://github.com/sailrish/shipit-api/edit/master/src/controllers/carrier.coffee`
2. Select all, delete, paste the above
3. Click **Commit changes** at the bottom
4. Wait ~60 seconds for Render to auto-deploy

Then test in your browser:
```
https://YOUR-APP.onrender.com/api/carriers/usps/YOUR_TRACKING_NUMBER
