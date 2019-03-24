-- Adapted from https://github.com/jkhsjdhjs/LedESP8266_esp-lua E.Floyd 2019-01-05
require "TaskQueue"
PCA9685 = {}
PCA9685.i2c = nil
PCA9685.address = nil
PCA9685.channel = nil
PCA9685.tmr_ref = nil
PCA9685.step_increment = 30 / 1000 -- seconds per step for fade (settle time for i2c and servo)

-- converts a channel number to the address of the first register which belongs to the specified channel (each channel has 4 registers)
-- params: channel
-- returns the first register for the specified channel
function PCA9685.channelToRegister(channel)
  return 0x06 + 0x04 * channel
end

-- read values from registers of the pca
-- params: starting register to read from, number of registers to read (default: 1)
-- returns value from 0x00 to 0xFF on success, false otherwise
function PCA9685:readRegister(reg, n)
  return self.i2c:readRegister(self.address, reg, n)
end

-- write values to registers of the pca
-- params: register to write in, values
-- returns true on success, false otherwise
function PCA9685:writeRegister(reg, ...)
  return self.i2c:writeRegister(self.address, reg, ...)
end

-- initialize the PCA9685 module
-- params: object returned by I2CLib:initialize(), i2c address of PCA9685, clock frequency in Hz
-- returns self on success, may throw error from I2CLib
function PCA9685:initialize(i2c, address, freq)
  self.i2c = i2c
  self.address = address
  self.clock = math.floor((25000000 / (4096 * freq)) - 1)
  self:writeRegister(0x00, 0x10) -- clock off
  self:writeRegister(0xFE, self.clock) -- set clock prescale
  self:writeRegister(0x00, 0x20) -- clock on + autoincr
  self:writeRegister(0x01, 0x04) -- totem pole
  return self
end

-- turn off the clock
function PCA9685:sleep()
  self:writeRegister(0x00, 0x10) -- clock off
end

-- turn on the clock
function PCA9685:wake()
  self:writeRegister(0x00, 0x20) -- clock on + autoincr
  self:writeRegister(0x01, 0x04) -- totem pole
end

-- set the PWM value of a specific channel
-- params: channel, pon, poff (values from 0x000 to 0xFFF)
--   (pon specifies beginning of the pulse, poff end of pulse)
-- returns true on success, false otherwise; may throw error from I2CLib
function PCA9685:setChannelPWM(channel, pon, poff)
  local register = self.channelToRegister(channel)
  return false ~= self:writeRegister(register,
    bit.band(pon, 0xff),
    bit.band(bit.rshift(pon, 8), 0x0f),
    bit.band(poff, 0xff),
    bit.band(bit.rshift(poff, 8), 0x0f)
  )
end

-- get the PWM value of a specific channel
-- params: channel
-- returns pon, poff (values from 0x000 to 0xFFF) on success, false otherwise
-- may throw error from I2CLib
function PCA9685:getChannelPWM(channel)
  local register = self.channelToRegister(channel)
  local ponlo, ponhi, pofflo, poffhi = self:readRegister(register, 4)
  if not ponlo then
    return false
  end
  return bit.bor(bit.lshift(bit.band(ponhi, 0x0f), 8), ponlo),
         bit.bor(bit.lshift(bit.band(poffhi, 0x0f), 8), pofflo)
end

-- fade from the current values to the specified values over a specified time
-- params: channel, target pon, target poff, fade time in seconds
function PCA9685:fadeChannelPWM(channel, pon, poff, seconds, callback)
  local pon1, poff1 = self:getChannelPWM(channel)
  coroutine.yield()
  pon = bit.band(pon, 0x0fff)
  poff = bit.band(poff, 0x0fff)
  local steps = math.max(1, math.floor(seconds / self.step_increment))
  local onstep = (pon - pon1) / steps
  local offstep = (poff - poff1) / steps
  local timer = tmr.create()
  local step = 1
  timer:alarm(self.step_increment * 1000, tmr.ALARM_AUTO, function()
    if step == steps then
      self:setChannelPWM(channel, pon, poff)
      timer:unregister()
      if type(callback) == 'function' then
        callback(self)
      end
    else
      pon1 = pon1 + onstep
      poff1 = poff1 + offstep
      self:setChannelPWM(channel, pon1, poff1)
      step = step + 1
    end
  end)
end
