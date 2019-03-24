--Stepper
require "TaskQueue"

GPIOSTEP = {}
-- Controls stepper moter using four gpio pins using gpio.pulse
-- Params:
--  s1, s2, s3, s4 - the four gpio pins
--  clock - the clock frequency in Hz (default 100)
-- Returns: initialized stepper control object
function GPIOSTEP:initialize(s1, s2, s3, s4, clock)
  gpio.mode(s1, gpio.OUTPUT)
  gpio.mode(s2, gpio.OUTPUT)
  gpio.mode(s3, gpio.OUTPUT)
  gpio.mode(s4, gpio.OUTPUT)
  local step_delay = (clock or 100) * 8
  local step_jitter = step_delay / 20
  local step_min = step_delay - step_jitter
  local step_max = step_delay + step_jitter
  -- print(step_delay, step_jitter, step_min, step_max)
  self._cw = gpio.pulse.build( {
    { [s1] = 1, [s2] = 0, [s3] = 0, [s4] = 0, delay=step_delay },
    { [s1] = 1, [s2] = 1, [s3] = 0, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 1, [s3] = 0, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 1, [s3] = 1, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 1, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 1, [s4] = 1, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 0, [s4] = 1, delay=step_delay },
    { [s1] = 1, [s2] = 0, [s3] = 0, [s4] = 1, delay=step_delay,
    loop=1, count=0, min=step_min, max=step_max },
    { [s1] = 0, [s2] = 0, [s3] = 0, [s4] = 0, delay=step_delay },
  })
  self._ccw = gpio.pulse.build( {
    { [s1] = 1, [s2] = 0, [s3] = 0, [s4] = 1, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 0, [s4] = 1, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 1, [s4] = 1, delay=step_delay },
    { [s1] = 0, [s2] = 0, [s3] = 1, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 1, [s3] = 1, [s4] = 0, delay=step_delay },
    { [s1] = 0, [s2] = 1, [s3] = 0, [s4] = 0, delay=step_delay },
    { [s1] = 1, [s2] = 1, [s3] = 0, [s4] = 0, delay=step_delay },
    { [s1] = 1, [s2] = 0, [s3] = 0, [s4] = 0, delay=step_delay,
    loop=1, count=0, min=step_min, max=step_max },
    { [s1] = 0, [s2] = 0, [s3] = 0, [s4] = 0, delay=step_delay },
  })
  return self
end

-- Step the stepper
-- Params:
--  steps - +/- number of steps to do with direction indicated by sign: + clockwise, - ccw
--  callback -(function) callback function (see gpio.pulse.start)
--            (number) timeout in seconds (can be fractional) to wait for completion
--            (true) wait for completion with no timeout
--            (nil or false) fire & forget, no callback, no wait
-- Returns: (pulser object) if callback is function or nil
--          (boolean) true if steps complete before timeout (callback == true)
function GPIOSTEP:step(steps, callback)
  local pulser = nil
  local upd = {}
  if steps > 0 then
    upd = { count = steps }
    pulser = self._cw
  else
    upd = { count = -steps }
    pulser = self._ccw
  end
  pulser:update(8, upd)
  if type(callback) == 'function' then
    pulser:start(callback)
  elseif callback then
    local done = Lock(true)
    pulser:start(function()
      done:release()
    end)
    return done:await(callback)
  else
    pulser:start(nil)
  end
  return pulser
end

GPIOSERVO = {}
-- Controls a servo with pwm
-- Params:
--  pin - the gpio pin number
--  freq - the pwm frequency in Hz
-- Returns: initialized servo control object in stopped state
function GPIOSERVO:initialize(pin, freq)
  self.pin = pin
  self.freq = freq
  pwm.setup(self.pin, self.freq, 100)
  pwm.stop(self.pin)
  return self
end

-- Sets duty cycle for servo
-- Params:
--  duty - duty cycle 0..1024.
--      note: generally servos want a number between 100 and 500
-- Returns: self
function GPIOSERVO:setPWM(duty)
  pwm.setduty(self.pin, duty)
  return self
end

-- Starts servo pwm
-- Returns: self
function GPIOSERVO:start()
  pwm.start(self.pin)
  return self
end

-- Stops servo pwm
function GPIOSERVO:stop()
  pwm.stop(self.pin)
end
