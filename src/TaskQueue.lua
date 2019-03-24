-- Lock primative similar to Python Lock
Lock = {
  __index = {

    -- returns true if locked
    is_locked = function(self)
      return self._locked
    end,

    -- waits for lock to become available with optional timeout
    -- returns false if timed out
    -- does not acquire lock
    await = function(self, delay)
      local timeout = nil
      if type(delay) == 'number' then
        timeout = TaskQueue:now() + delay * 1000000
      end
      while self._locked do
        coroutine.yield()
        if timeout and TaskQueue:now() >= timeout then
          return false
        end
      end
      return true
    end,

    -- acquires lock with optional timeout
    -- returns false if timed out
    acquire = function(self, delay)
      if self:await(delay) then
        self._locked = true
        return true
      end
      return false
    end,

    -- releases lock
    release = function(self)
      self._locked = false
    end,
  },

  __call = function(cls, locked)
    return setmetatable({_locked=locked}, cls)
  end
}
setmetatable(Lock, Lock)

-- runnable task tracking object
Task = {
  __index = {

    -- Returns statistics for this task:
    --  number of dispatches
    --  total time dispatched in microseconds
    --  maximum time for any dispatch in microseconds
    stats = function(self)
      return self._disp, self._time, self._max
    end,

    -- Await task termination
    await = Lock.await,

    -- Indicate task is terminated
    release = Lock.release,

    -- Returns true if task is active
    is_active = Lock.is_locked,
  },

  __call = function(cls, func)
    return setmetatable({_cortn=coroutine.create(func),_locked=true}, cls)
  end
}
setmetatable(Task, Task)

-- simple priority queue with task dispatcher
TaskQueue = {
  __index = {

    -- Skew heap, thanks to Gé Weijers!
    _rmeld = function(a, b)
      if a and b then
        if a.key < b.key then
          a.left, a.right = a.right, TaskQueue._rmeld(a.left, b)
          return a
        else
          b.left, b.right = b.right, TaskQueue._rmeld(a, b.left)
          return b
        end
      else
        return a or b
      end
    end,

    -- Override to monitor events.
    -- Params:
    --  event - a table with one or two keys:
    --    'type': event type, one of:
    --      'schedule' - task scheduled, obj is Task
    --      'end' - task terminated, obj is Task
    --      'start' - task dispatching started, no obj
    --      'stop' - task dispatching stopped, no obj
    --    'obj': object associated with type, if any
    event = function(self, event)
    end,

    -- Puts value v on heap with priority p
    -- Params:
    --  p - priority, typically a time from the microsecond clock. Can be any comparable.
    --  v - value associated with p
    -- Returns: self
    put = function(self, p, v)
      self._q = TaskQueue._rmeld(self._q, {key=p, val=v})
      self._qn = self._qn + 1
      return self
    end,

    -- Removes and returns highest priority key and value
    -- Returns: p, v
    pop = function(self)
      local ret = self._q
      if ret then
        self._q = TaskQueue._rmeld(self._q.left, self._q.right)
        self._qn = self._qn - 1
        ret.left, ret.right = nil, nil
        return ret.key, ret.val
      end
    end,

    -- Returns microsecond clock with no overflow
    -- Must be called at least every few minutes
    now = function(self)
      local now = tmr.now()
      local inc = now - TaskQueue._now
      TaskQueue._now = now
      if inc < 0 then
        inc = inc + 0x80000000
      end
      TaskQueue._clock = TaskQueue._clock + inc
      return TaskQueue._clock
    end,

    -- Schedules a new task
    -- Params:
    --  delay - delay in seconds before first dispatch (can be fractional, like: 0.1)
    --  func - function to dispatch, or can be a Task object
    --  ... - parameters to pass to the task function
    -- Returns: Task object
    schedule = function(self, delay, func, ...)
      local now = TaskQueue:now()
      local task = nil
      if type(func) == 'function' then
        task = Task(func)
      else
        -- assume task has been separately constructed
        task = func
      end
      task._tq = self
      task._args = arg or {}
      task._time = 0
      task._disp = 0
      task._max = 0
      local when = now + (delay or 0) * 1000000
      self:put(when, task)
      self:event({type='schedule',obj=task})
      return task
    end,

    -- Dispatches the highest priority Task on the queue
    dispatch = function(self)
      -- always update the clock
      local now = TaskQueue:now()
      local item = self._q
      if not self._active and self._running and item and now >= item.key then
        -- no active dispatches, running, and we have a ready task
        self._active = true
        -- for some reason we have to collectgarbage() before every dispatch
        node.task.post(1, function() collectgarbage() end)
        -- tasks run on the low priority queue
        node.task.post(0, function()
          -- LOW PRIORITY TASK
          -- actual dispatching happens here
          -- there may have been a delay, so we need to re-fetch the ready task
          local now = TaskQueue:now()
          local item = self._q
          -- inline remove from the queue (see pop())
          self._q = TaskQueue._rmeld(item.left, item.right)
          task, item.left, item.right = item.val
          -- dispatch it
          local status, delay = coroutine.resume(task._cortn, task, unpack(task._args))
          local incr = TaskQueue:now() - now
          task._disp = task._disp + 1
          task._time = task._time + incr
          if incr > task._max then
            task._max = incr
          end
          if coroutine.status(task._cortn) == 'dead' then
            -- task has ended - clean up for gc
            self._qn = self._qn - 1
            if type(task.final) == 'function' then
              -- call the finalizer, if provided
              pcall(task.final, task, status, delay, unpack(task._args))
            end
            self:event({type='end',obj=task})
            task:release()
            task._tq, task._cortn, task._args, item.key, item.val, item, task = nil
          else
            -- re-queue the task with possible delay
            item.key = now + math.max(0, (delay or 0)) * 1000000
            self._q = TaskQueue._rmeld(self._q, item)
          end
          self._active = nil
          -- END OF LOW PRIORITY TASK
        end)
      end
    end,

    -- Starts the dispatcher
    start = function(self)
      if not self._dtimer then
        self._dtimer = tmr.create()
        self._dtimer:alarm(self._slack, tmr.ALARM_AUTO, function()
          self:dispatch()
        end)
      end
      if not self._running then
        self._running = true
        self:event({type='start'})
      end
    end,

    -- Stops the dispatcher
    stop = function(self)
      if self._running then
        self._running = false
        self:event({type='stop'})
      end
    end,

    -- Returns dispatcher status
    -- Returns: running, queue_count, slack
    --  running - boolean, true if scheduler is running
    --  queue_count - number of Tasks in the queue
    --  slack - minimum time between dispatches (see below)
    status = function(self)
      return self._running, self._qn, self._slack
    end,

    -- Sets slack time between dispatches
    -- Params: ms - milliseconds slack time
    set_slack = function(self, ms)
      if type(ms) ~= 'number' or ms < 1 then
        self._slack = 2
      else
        self._slack = math.floor(ms)
      end
      if self._dtimer then
        self._dtimer:interval(self._slack)
      end
    end,
  },

  __call = function(cls)
    return setmetatable({_q=nil,_qn=0,_running=false,_slack=2}, cls)
  end
}
setmetatable(TaskQueue, TaskQueue)
if not TaskQueue._timer then
  -- set up clock
  TaskQueue._clock = 0
  TaskQueue._now = tmr.now()
  TaskQueue._timer = tmr.create()
  TaskQueue._timer:alarm(1000, tmr.ALARM_AUTO, function()
    -- ensure that the clock gets updated regularly
    TaskQueue:now()
  end)
end
node.egc.setmode(node.egc.ON_ALLOC_FAILURE)
