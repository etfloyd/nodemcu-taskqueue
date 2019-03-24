require "TaskQueue"
WIFILib = {}
WIFILib.save = false
WIFILib.mode = wifi.STATION
WIFILib.country = 'US'

-- initialize WIFILib
-- params:
--  country (string)  - country code, default: "US"
--  save (boolean)    - save configuration in flash memory
--  station (boolean) - station mode
--  ap (boolean)      - access point mode
--  ssid (string)     - SSID for ap mode
--  pwd (string)      - password for ap mode
-- returns: initialized WIFILib object
function WIFILib:initialize(country, save, station, ap, ssid, pwd)
  self.save = save
  if station and ap then
    self.mode = wifi.STATIONAP
  elseif ap then
    self.mode = wifi.SOFTAP
  end
  if country then
    self.country = country
  end
  wifi.setcountry({country=self.country, start_ch=1, end_ch=13, policy=wifi.COUNTRY_AUTO})
  wifi.setmode(self.mode, self.save)
  if ap then
    local cfg = {save=self.save}
    if pwd then
      cfg.pwd = pwd
      cfg.auth = wifi.WPA2_PSK
    end
    if ssid then
      cfg.ssid = ssid
    end
    wifi.ap.config(cfg)
  end
  return self
end

-- put wifi to sleep to reduce power consumption
function WIFILib:sleep()
  return wifi.setmode(wifi.NULLMODE, self.save)
end

-- wake up wifi
function WIFILib:wake()
  return wifi.setmode(self.mode, self.save)
end

-- Listen for client connects and/or disconnects (ap mode)
-- params:
--  staconnected_cb (function)    - callback for station connect event
--  stadisconnected_cb (function) - callback for station disconnect event
function WIFILib:listen(staconnected_cb, stadisconnected_cb)
  if type(staconnected_cb) == 'function' then
    wifi.eventmon.register(wifi.eventmon.AP_STACONNECTED, staconnected_cb)
  else
    wifi.eventmon.unregister(wifi.eventmon.AP_STACONNECTED)
  end
  if type(stadisconnected_cb) == 'function' then
    wifi.eventmon.register(wifi.eventmon.AP_STADISCONNECTED, stadisconnected_cb)
  else
    wifi.eventmon.unregister(wifi.eventmon.AP_STADISCONNECTED)
  end
end

-- return IP address of connected client
-- params:
--  mac (string)    - mac address of client
--  delay (seconds) - seconds to wait for IP
function WIFILib:get_client_ip(mac, delay)
  local ip = wifi.ap.getclient()[mac]
  local timeout = nil
  if delay then
    timeout = TaskQueue:now() + delay * 1000000
  end
  while not ip do
    coroutine.yield()
    if timeout and TaskQueue:now() >= timeout then
      return false
    end
    ip = wifi.ap.getclient()[mac]
  end
  return ip
end

-- connect to access point (station mode)
-- params:
--  ssid (string)       - SSID of ap to which to connect
--  pwd (string)        - password for connection
--  callback (function) - callback function
--            (number) timeout in seconds (can be fractional) to wait for completion
--            (true) wait for completion with no timeout
--            (nil or false) fire & forget, no callback, no wait
function WIFILib:connect(ssid, pwd, callback)
  local cfg = {auto=true, save=self.save}
  if ssid then
    cfg.ssid = ssid
  end
  if pwd then
    cfg.pwd = pwd
  end
  if type(callback) == 'function' then
    -- caller provides callback function
    cfg.got_ip_cb = callback
  elseif callback then
    -- synchronous connect with optional timeout
    local connected = Lock(true)
    connected.t = nil
    cfg.got_ip_cb = function(t)
      connected.t = t
      connected:release()
    end
    wifi.sta.config(cfg)
    connected:await(callback)
    return connected.t
  end
  -- asynchronous connect
  return wifi.sta.config(cfg)
end

-- disconnect from access point (station mode)
function WIFILib:disconnect()
  wifi.sta.config({auto=false, save=self.save})
  coroutine.yield()
  return wifi.sta.disconnect()
end

-- get table of access points (station mode)
-- params
--  callback (function) - callback function (see wifi.sta.getap())
--            (number) timeout in seconds (can be fractional) to wait for completion
--            (true) wait for completion with no timeout
--            (nil or false) fire & forget, no callback, no wait
-- returns:
--  wifi.sta.getap() object if callback function or false or nil
--  result table if callback number or true and completes before timeout
--  nil if timeout
function WIFILib:getap(callback)
  if type(callback) == 'function' then
    return wifi.sta.getap({hidden=0}, callback)
  elseif callback then
    local getap = Lock(true)
    getap.t = nil
    wifi.sta.getap({ hidden = 0 }, 1, function(t)
      print("getap callback!")
      getap.t = t
      getap:release()
    end)
    getap:await(callback)
    return getap.t
  end
  return wifi.sta.getap({hidden=0})
end
