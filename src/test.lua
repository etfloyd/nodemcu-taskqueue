node.setcpufreq(node.CPU160MHZ)

------------------------------
-- Setup and common functions
------------------------------

function printHeap(x)
  print("---heap "..x..":", node.heap())
end

printHeap("at beginning")

require "TaskQueue"
require "I2CLib"
require "PCA9685"
require "GPIOSTEP"
require "WIFILib"

printHeap("after requires")

if not tq then
  -- Create task queue
  tq = TaskQueue()
  tq:start()
  printHeap('after tq created')
end

if not wf then
  -- Initialize wifi
  wf = WIFILib:initialize('US', true, true, true, 'EF8266', 'password')
  -- Set these manually from the console before running test()
  myssid = nil
  mypass = nil
  printHeap('after wf created')
end

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

-- adds items to queue
-- Params:
--  x - ident string (arbitrary)
--  q - the queue (an instance of TaskQueue)
--  n - number of elements to add
function loadQueue(x, q, n)
  printHeap('before '..x)
  for j = 1, n do
    local k = tmr.now()+math.random(100000)
    q:put(k, x.." "..j)
    coroutine.yield()
  end
  printHeap('after '..x)
  return n
end

-- prints items from queue
-- Params:
--  x - ident string (arbitrary)
--  q - the queue (an instance of TaskQueue)
function printQueue(x, q)
  printHeap('before '..x)
  local k, v = q.pop()
  while k do
    print(k, v)
    coroutine.yield()
    k, v = q:pop()
  end
  printHeap('after '..x)
end

------------------------------
-- Task functions for tests
------------------------------

-- Test wifi, gets AP list and attempts to connect to local ap
function wifitest(self, id)
  -- ==WifiTest task function
  self.final = print_status
  print(id, 'Started')
  collectgarbage()
  printHeap('at start of wifitest()')

  -- Start listening for client connections
  wf:listen(function(t)
    -- Callback: client has connected!
    print("WiFi Client Connected!")
    -- schedule a task to handle the connection
    tq:schedule(nil, function(self, id, t)
      -- ==CLIENT task function
      self.final = print_status
      print(id, "Started")
      print(id, "Getting IP")
      local ip = wf:get_client_ip(t.MAC, 5)
      if not ip then
        print(id, "Timed out getting IP")
      end
      print("   MAC:", t.MAC, "AID:", t.AID, "IP: ", ip)
    end, '==CLIENT'..t.MAC, t)
  end, function(t)
    -- Callback: client has disconnected!
    print("WiFi Client Disconnected!")
    print("   MAC:", t.MAC, "AID:", t.AID)
  end)
  printHeap('after wf:listen()')

  print(id, 'getap')
  local t = wf:getap(15)
  if t then
    print("\n"..string.format("%32s","SSID").."\tBSSID\t\t\t\tRSSI\tAUTHMODE\tCHANNEL")
    local count = 0
    coroutine.yield()
    for bssid,v in pairs(t) do
        count = count + 1
        local ssid, rssi, authmode, channel = string.match(v, "([^,]+),([^,]+),([^,]+),([^,]*)")
        print(string.format("%32s",ssid).."\t"..bssid.."\t"..rssi.."\t\t"..authmode.."\t\t\t"..channel)
        coroutine.yield()
    end
    print("-- Total APs: ", count)
  else
    print("Timeout waiting for ap list")
  end
  print(id, 'connect')
  t = wf:connect(myssid, mypass, 10)
  if t then
    print("Connected! IP:", t.IP, 'netmask:', t.netmask, 'gateway:', t.gateway)
  else
    print("Timeout waiting for connect")
  end
end

-- Test gpio.pulse based stepper motor
-- Rotates 100 steps clockwise, waits 3 seconds, rotates 100 steps ccw
function steptest(self, id)
  -- ==StepTest task function
  self.final = print_status
  print(id, "Started")
  local stepper = GPIOSTEP:initialize(1, 2, 3, 4, 100)
  printHeap('after stepper created')
  print(id, "stepping clockwise")
  if not stepper:step(100, 10) then
    print(id, "Step1 timeout")
  end
  coroutine.yield(3)
  print(id, "stepping counterclockwise")
  if not stepper:step(-100, 10) then
    print(id, "Step2 timeout")
  end
end

-- Grabs and holds blocker Lock for 5 seconds, then releases and ends
function t1(self, id, xx)
  -- ==First task function
  self.final = print_status
  print(id, "Started", xx)
  print(id,"First task")
  if blocker:acquire(1) then
    print(id,"First task got blocker")
    coroutine.yield(5)
    blocker:release()
    print(id,"First task released blocker")
  else
    print(id,"First task timed out")
  end
  coroutine.yield()
  print(id,"First task ending")
end

-- Starts and immediately throws an error
function t2(self, id)
  -- ==Second task function
  self.final = print_status
  print(id, "Started")
  print(id,"Second task")
  error(id..":Oops!! (Deliberate error)")
  coroutine.yield()
end

-- Waits up to 3 seconds for blocker Lock.
-- this task should time out if started immediately after t1
function t3(self, id)
  -- ==Third task function
  self.final = print_status
  print(id, "Started")
  print(id, "Blocked task")
  if blocker:acquire(3) then
    print(id, "Blocked task got blocker")
    blocker:release()
    print(id,"Blocked task released blocker")
  else
    print(id,"Blocked task timed out")
  end
  coroutine.yield()
  print(id,"Blocked task ending")
end

-- Waits up to 6 seconds for blocker Lock.
-- this task should succeed if started immediately after t1
function t4(self, id)
  -- ==Fourth task function
  self.final = print_status
  print(id, "Started")
  print(id,"Blocked task")
  if blocker:acquire(6) then
    print(id,"Blocked task got blocker")
    blocker:release()
    print(id,"Blocked task released blocker")
  else
    print(id,"Blocked task timed out")
  end
  coroutine.yield()
  print(id,"Blocked task ending")
end

------------------------------
-- Mainline test functions
------------------------------

-- test TaskQueue scheduler
function test()
  collectgarbage()
  printHeap('at start of test()')
  local inserted = 0
  local pq = TaskQueue()
  printHeap('after pq created')

  local blocker = Lock()

  -- Schedule TaskQueue, wifi, and stepper tests
  tq:schedule(nil, t1, '==First', 'another parameter xx')
  tq:schedule(2, t2, '==Second')
  tq:schedule(nil, t3, '==Third')
  tq:schedule(nil, t4, '==Fourth')
  tq:schedule(nil, wifitest, '==WifiTest')
  tq:schedule(nil, steptest, '==StepTest')

  -- chew up some memory
  local first = tq:schedule(nil, function(self, id)
    -- ==LQ1 task function
    self.final = print_status
    print(id, "Started")
    inserted = inserted + loadQueue('Load'..id, pq, 20)
    coroutine.yield()
  end, '==LQ1')

  -- and some more memory
  local second = tq:schedule(nil, function(self, id)
    -- ==LQ2 task function
    self.final = print_status
    print(id, "Started")
    first:await()
    inserted = inserted + loadQueue('Load'..id, pq, 20)
    coroutine.yield()
  end, '==LQ2')

  -- now print out the items in pq in priority order
  local pqprint = tq:schedule(nil, function(self, id)
    -- ==PQ task function
    self.final = print_status
    print(id, "Started")
    if first:await(5) and second:await(5) then
      print(id, inserted, 'items loaded')
      printQueue("Print"..id, pq)
      coroutine.yield()
    else
      print(id, 'Timeout waiting for load! Tasks active:')
      print(id, 'first:', first:is_active())
      print(id, 'second:', second:is_active())
    end
  end, '==PQ')

  -- finally, schedule a Task to clean up and print heap
  tq:schedule(10, function(self, id)
    -- ==GARBAGE task function
    self.final = print_status
    print(id, "Started")
    blocker:release()
    first:release()
    second:release()
    coroutine.yield()
    pq, inserted, first, second, pqprint = nil
    coroutine.yield()
    printHeap('gc'..id)
  end, '==GARBAGE')

  printHeap('after all test scheduled')
end

-- Test PCA9685
-- Note: requires PCA9682 hardware
function pcatest()
  printHeap('at start of testpca')
  if not (icl and pca) then
    icl = I2CLib:initialize(6, 7)
    pca = PCA9685:initialize(icl, 0x40, 50)
    printHeap('after icl and pca created')
  end
  local maxchannel = 4

  tq:schedule(nil, function(self, id)
    -- ==TestPMW task function
    self.final = print_status
    print(id,'Started')
    pca:wake()
    coroutine.yield()
    -- set all servos to appx zero degrees
    for j = 0, maxchannel do
      pca:setChannelPWM(j, 0, 101)
      coroutine.yield()
    end
    -- retrieve and print channel PWM values
    for j = 0, maxchannel do
      print(pca:getChannelPWM(j))
      coroutine.yield()
    end
    print(id, "Waiting 2 seconds")
    coroutine.yield(2)
    local rondevous = 0
    -- set all servos to appx 180 degrees over a period that varies by channel
    -- (period in seconds is channel number + 1)
    for j = 0, maxchannel do
      rondevous = rondevous + 1
      seconds = j + 1 -- arbitrary!
      pca:fadeChannelPWM(j, 0, 500, seconds, function()
        rondevous = rondevous - 1
      end)
      coroutine.yield()
    end
    print(id, 'Waiting for fades to complete')
    while rondevous > 0 do
      coroutine.yield()
    end
    -- retrieve and print channel PWM values
    for j = 0, maxchannel do
      print(pca:getChannelPWM(j))
      coroutine.yield()
    end
  end, '==TestPWM')
end

printHeap('after require test')
