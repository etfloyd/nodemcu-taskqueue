-- This lib is an extension for the NodeMCU i2c module and still requires it to run.
-- Adapted from https://github.com/jkhsjdhjs/LedESP8266_esp-lua E.Floyd 2019-01-05
require "TaskQueue"
I2CLib = {}
I2CLib.id = nil

-- called whenever an error condition occurs below
-- default just calls system error()
-- can be overridden in initialize()
function I2CLib:error(msg)
  error(msg)
  -- alternative errorfunc, e.g.:
  -- print(msg)
  -- return nil
end

-- init i2c bus
-- params: sda pin, scl pin, optional error function
--         (for pin numbers see: https://nodemcu.readthedocs.io/en/master/en/modules/gpio/)
-- returns an initialized I2CLib object
function I2CLib:initialize(sda, scl, errorfunc)
  if self.id then
    return self:error("I2CLib already initialized")
  else
    self.id = 0
    i2c.setup(self.id, sda, scl, i2c.SLOW)
    if type(errorfunc) == 'function' then
      self.error = errorfunc
    end
  end
  return self
end

-- check if a specific device exists
-- params: i2c id, device address
-- returns true if device exists, false otherwise
function I2CLib:deviceExists(dev)
  i2c.start(self.id)
  local exists = i2c.address(self.id, dev, i2c.TRANSMITTER)
  i2c.stop(self.id)
  return not (not exists)
end

-- list connected devices
-- params: i2c id
-- returns a table with addresses of connected devices
function I2CLib:detectDevices()
  local dev = {}
  for i = 0, 127 do
    if self:deviceExists(i) then
      dev[#dev + 1] = i
    end
  end
  return dev
end

-- read register(s)
-- params: i2c id, device address, starting register, optional number to read (default 1)
-- returns value(s) from 0 - 255 on success and false on fail
function I2CLib:readRegister(dev, reg, n)
  local rv = nil
  i2c.start(self.id)
  if i2c.address(self.id, dev, i2c.TRANSMITTER) then
    i2c.write(self.id, reg)
    i2c.stop(self.id)
    i2c.start(self.id)
    if i2c.address(self.id, dev, i2c.RECEIVER) then
      rv = i2c.read(self.id, n or 1)
      i2c.stop(self.id)
      return string.byte(rv, 1, #rv)
    end
  end
  i2c.stop(self.id)
  return self:error("device_not_found:"..dev)
end

-- write register
-- params: i2c id, device address, register, data to write
-- returns true on success, false otherwise
function I2CLib:writeRegister(dev, reg, ...)
  i2c.start(self.id)
  if i2c.address(self.id, dev, i2c.TRANSMITTER) then
    if i2c.write(self.id, reg, ...) == select("#", ...)+1 then
      i2c.stop(self.id)
      return true
    end
    i2c.stop(self.id)
    return self:error("failed_write_register:"..reg.." on dev:"..dev)
  end
  i2c.stop(self.id)
  return self:error("device_not_found:"..dev)
end
