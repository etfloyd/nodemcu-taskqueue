# **TaskQueue 0.1.0** #

### Lua Cooperative Multitasking for NodeMCU

##### TL;DR

The TaksQueue.lua module provides a simple, low-overhead coroutine-based concurrent Task manager in which a Task can at any time call `coroutine.yield([seconds])` to return control to the SDK event loop and allow other Tasks to be dispatched. It also provides a 'Lock' primative for coordination between Tasks and callbacks. `TaskQueue.lua` and `Lock.lua` facilitate inline coding of complex multiple dependent actions that would otherwise be coded as deeply-nested callbacks, chained timers, fifo queues or other less-intiutive workarounds.

##### Status

Work in progress. The TaskQueue module itself is fairly well-tested and fully documented. The I2CLib, PCA9685, and GPIOSTEP modules are tested but not fully documented, other than source comments. WIFILib is just a start. I2CLib and WIFILib are "wrappers" around existing functionality. They are intended to simplify use of I2C and WiFi in TaskQueue Tasks but are nowhere near functionally complete.

##### Overview
In the this and the following sections, we will use "Task" (capitalized) to indicate a TaskQueue Task and "node task" (non-capitalized) to indicate a node.task.post() task.

[NodeMCU firmware](https://github.com/nodemcu/nodemcu-firmware) for for the ESP8266 provides a Lua-based development enviroment for the ESP8266 MCU that has the potential of greatly speeding up application development on these remarkable little computers. The standard environment requires an [event-driven approach](https://nodemcu.readthedocs.io/en/dev/lua-developer-faq/#so-how-does-the-sdk-event-tasking-system-work-in-lua) with callbacks that can be non-intuitive to begin with, especially for programmers who have never written for other event-driven systems like Java Swing or node.js. This becomes more evident with increasing code length and complexity, especially with ongoing maintenance and enhancememt activities. In addition, the rather strict time constraints on Lua code segments creates some special challenges. This project offers an alternative or perhaps more a complement to event-driven coding.

Here's a somewhat contrived example. First, coded with standard NodeMCU callbacks:

```lua
wifi.setcountry({country='US', start_ch=1, end_ch=13, policy=wifi.COUNTRY_AUTO})
wifi.setmode(wifi.STATION, true)
local cfg = {auto=true, save=true}
wifi.sta.config({auto=true, save=true, ssid='myssid', pwd='mypassword'})
tmr.alarm(0, 1000, 1, function()
  -- check once per second
  if wifi.sta.getip()==nil then
    print("connecting to AP...")
  else
    -- connected to ap
    print('ip: ',wifi.sta.getip())
    local skt = net.createConnection(net.TCP)
    skt:connect(8080, 1.2.3.4)
    skt:on('connection', function()
      -- connected to server
      skt.send('some data', function()
      -- do the next thing, function(done)
        -- and then the next, function(done)
          -- etc
            -- etc
              -- etc
              -- end)
            -- end)
          -- end)
        -- end)
      -- end)
      end)
    end)
    tmr.stop(0)
  end
end)
```
The example deliberately exaggerates the nesting which can be somewhat mitigated by breaking it up into separate functions or additional tmr.alarm sections at the cost of readability. Even then, what do you do with error conditions? What if the connection never completes? Where do you code timeouts?

So, here's a rather contrived example using TaskQueue and one of the associated convenience libraries, WiFiLib:
```lua
require "TaskQueue"
require "WIFILib"
tq = TaskQueue()
tq:start()
wf = WIFILib:initialize('US', true, true)
-- country: 'US', Save: true, Station: true
tq:schedule(0, function()
  -- in the task function
  local ip = wf:connect('myssid', 'mypassword', 10)
  -- 10-second timeout, returns control to SDK while waiting
  if ip then
    print("Connected to ap with IP", ip)
  else
    error("Timed out after 10 seconds")
  end
  -- example of inlining a callback using Lock
  local skt = net.createConnection(net.TCP)
  local done = Lock(true)
  -- Lock(true) sets the lock on creation
  skt:connect(8080, 1.2.3.4)
  skt:on('connection', function()
    -- inside the socket connect callback
    done:release()
  end)
  if not done:await(10) then
    -- returns control to SDK while waiting
    error("Timed out waiting 10 sec for server connect")
  end
  done = Lock(true)
  skt:send('some data', function(result)
    -- inside the send callback
    -- save the result, if any, in the Lock object
    done.result = result
    done:release()
  end)
  if not done:await(5) then
    -- returns control to the SDK while waiting
    error("Timed out waiting for send")
  end
  -- handle the result stored in 'done', if any
  -- do the next thing
  -- do the next thing
  -- etc
  -- etc
  -- etc
end)

```
This is longer but it does more. It handles timeouts and error conditions and I would submit that it's a lot easier to read and figure out what's going on than it would be with a nested callback or multiple timer approach.

Here's an example of something you can do with Tasks that would be significantly more difficult and less readable otherwise:

```lua
require "TaskQueue"
tq = TaskQueue()
tq:start()
-- Generic finalizer, prints task stats at termination
function print_status(task, ok, msg, id)
  if not ok then
    print(id, 'ERROR:', msg)
  end
  local disp, time, max = task:stats()
  time = time / 1000
  max = max / 1000
  print(id, 'STATS Total ms:', time, 'Avg ms:', time / disp, 'Max ms:', max)
  print(id, 'ENDED')
end
-- schedule a task that includes a long-running computation
local comptask = tq:schedule(0, function(self, id)
  print('Task', id, 'started')
  self.final = print_status
  --do something
  --now, a long-running computation
  local k = 1
  for j = 1, 100000 do
    k = k / 12.345 + math.random(1000000) / 2345.678 * k + k * 0.12345
    --let sleeping watchdogs lie!
    coroutine.yield()
  end
end,'--ComputeTask')
-- schedule another task to run concurrently
tq:schedule(0, function()
  print('Task', id, 'started')
  self.final = print_status
  --do something
  comptask:await() -- wait for the first task to complete
  coroutine.yield(2.5) -- pause for appx 2.5 seconds
  --do some other stuff
  coroutine.yield() -- yield to SDK
  --more stuff
  --etc
end,'--OtherTask')
```
The first Task schedules a long-running computation. In this case, it yields to the SDK after every iteration. The second Task runs concurrently, does some stuff, then yields to the SDK while waiting for the first task to complete, then pauses approximately 2.5 seconds during which it yields to the SDK, then does more stuff. Both Tasks are given identifiers via the third parameter of the the tq:schedule() method.

At the end of each Task, if running on something that shows console output, we'll get a printout of the total, average, and max execution time used by each task between yields to the SDK. This can help us tune our Lua code for optimum performance while playing nice with other processes.

So, let's say you have eight servos and a stepper motor and you want to orchestrate these on the fly with script fragments uploaded via WiFi such that the servos operate four coordinated legs for walking and the stepper for pointing a sensor or camera. How would you approach this with nothing but callbacks? How would you approach it with TaskQueue and Lock? Which approach do you think might be easier to debug and maintain?

The down side? There are a few:
1. You tend not to get as 'tight' code with this technique.
2. Timings using `coroutine.yield(delay)` are not precise. Timings can vary significantly compared to raw tmr or real-time clock timings. Though most likely variations of a few milliseconds would be barely noticible on a human scale, you wouldn't want to use `coroutine.yield()` timings where electronic precision is required.
3. Modules tend to be longer. For that reason, it is highly recommended to leverage LFS for TaskQueue designs.

##### How It Works

TaskQueue Tasks are actually [coroutines](https://www.lua.org/pil/9.1.html). TaskQueue.lua implements a priority queue for Task scheduling, a non-overflowing microsecond clock, and an event loop for dispatching Task coroutines. Tasks are prioritized by the time after which they may next be dispatched. The event loop is implemented as a tmr.alarm() that fires at regular intervals, generally every one or two milliseconds, and dispatches Tasks something like this (see the actual source code for details):

1. Examine the Task at the top of the priority queue - the one with the earliest time to next dispatch - and compare its dispatch time with the current clock time. If the time has not yet arrived to dispatch that Task, or if a Task is already being dispatched, skip the remaining steps and wait for the next alarm to fire.
2. Set a flag indicating that a Task is being dispatched.
3. Post garbage collection node task on the medium priority queue with: node.task.post(1, function() collectgarbage() end). This ensures that the Task will have as much memory as possible.
4. Post the dispatcher as a node task on the low priority queue. When the dispatcher runs, it does the following:
5. Remove the Task from the priority queue and coroutine.resume() it to dispatch the next segment.
6. After the Task segment returns from the resume(), update run time stats and check the coroutine status.
7. If the coroutine has crashed or ended normally, run the finalizer, if any, and clean up.
8. If the coroutine has yield()ed, compute the clock time when it may next be dispatched (either now or now + sleep time from the yield) and push it back on to the priority queue.
9. Reset the flag indicating that a Task is being dispatched.

The result is that Task segments execute serially as low priority node tasks between yield()s and each time a Task calls coroutine.yield(), the SDK event loop gets control so that it can itself dispatch higher priority node tasks. Task segments are executed as low priority node tasks because these can apparently tolerate longer run times than other kinds of node tasks.
