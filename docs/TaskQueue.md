# TaskQueue Module
| Since  | Origin / Contributor  | Maintainer  | Source  |
| :----- | :-------------------- | :---------- | :------ |
| 2019-01-05 | [ETFloyd](https://github.com/ETFloyd) | [ETFloyd](https://github.com/ETFloyd) | [TaskQueue.lua](../src/TaskQueue.lua) |

This Lua module provides a simple priority queue, non-overflowing microsecond clock, concurrent Task manager, and Lock synchronization primative.

### Require
```lua
require("TaskQueue")
tq = TaskQueue()
tq.start() -- if using as a Task manager
```
## TaskQueue.put()
Puts a value on the priority queue. This method is safe to call from any context if using the TaskQueue instance only as a priority queue. Do not call this method if using the TaskQueue instance as a Task manager. Use Task.schedule() instead.
#### Syntax
```lua
tq:put(key, value)
```
#### Parameters
- `key`: The priority associated with the value. This can be any comparable. For Tasks, the priority is TaskQueue:now() plus possibly some additional delay time.
- `value`: The value associated with the priority key. For Tasks, this is the Task instance.

#### Returns
`self` (tq)

## TaskQueue.pop()
Returns the highest priority (smallest key) and value from the queue. This method is safe to call from any context if using the TaskQueue instance only as a priority queue. Do not call this method if using the TaskQueue instance as a Task manager.
#### Syntax
```lua
local k, v = tq:pop()
```
#### Parameters
None
#### Returns
Key and value of the highest priority entry in the queue.

## TaskQueue.event()
Called by the TaskQueue dispatcher to signal Task manager events. Don't call this yourself. Only the dispatcher should call this.
#### Syntax
```lua
tq = TaskQueue()
tq.event = function(self, event)
  print(event.type)
end
```
#### Parameters
* `self`: the TaskQueue instance
* `event`: a table with one or two keys:
  * `type`: event type, one of:
    - 'schedule' - task scheduled, obj is Task
    - 'end' - task terminated, obj is Task
    - 'start' - task dispatching started, no obj
    - 'stop' - task dispatching stopped, no obj
  * `obj`: object associated with type, if any

#### Returns
N/A

## TaskQueue.now()
Non-overflowing microsecond clock. It is safe to call this from any context.

#### Syntax
```lua
local now = TaskQueue:now()
```
#### Parameters
None
#### Returns
Number of microseconds since require("TaskQueue") + the value of tmr.now() at that time.

## TaskQueue.schedule()
Schedule a Task for execution. It is safe to schedule a Task from any context.

#### Syntax
```lua
local task = tq:schedule(delay, function(self,...)
  --do something
  coroutine.yield() -- yield to SDK and other Tasks
  --do more
  coroutine.yield(2.5) -- yield for at least 2.5 seconds
  --do yet more
end, ...)
```
Note: `coroutine.yield(delay)` is not intended for precise timing.
#### Parameters
- `delay`: Number of seconds to delay before starting the Task. May be fractional.
- `function`: The function to be dispatched by TaskQueue as a coroutine. When running under TaskQueue, the first parameter (self) on this function is its Task instance. Any other parameters on the tq:schedule() call are added to the function call after 'self'.
- `...`: Additional arguments added to the Task function call.

#### Returns
The Task instance.

## TaskQueue.dispatch()
Dispatches the highest priority task on the queue. Don't call this yourself. Only the dispatch timer alarm should call this.

#### Syntax
```lua
-- in the dispatch timer alarm callback:
self:dispatch()
```
#### Parameters
None
#### Returns
nil

## TaskQueue.start()
Starts the dispatch timer alarm. The Task manager begins dispatching Tasks. It is safe to call this from any context.
#### Syntax
```lua
tq:start()
```
#### Parameters
None
#### Returns
nil

## TaskQueue.stop()
Stops the dispatch timer alarm. The Task manager stops dispatching Tasks. It is safe to call this from any context.
#### Syntax
```lua
tq:stop()
```
#### Parameters
None
#### Returns
nil

## TaskQueue.status()
Returns statistics from the TaskQueue instance. It is safe to call this from any context.
#### Syntax
```lua
local running, qn, slack = tq:status()
```
#### Parameters
None
#### Returns
- `running`: True if dispatcher is running.
- `qn`: Number of items (Tasks) in the queue.
- `slack`: Minimum time in milliseconds between successive dispatches.

## TaskQueue.set_slack()
Sets the dispatch timer alarm delay which determines the minimum interval between successive dispatches. It is safe to call this from any context.
#### Syntax
```lua
tq:set_slack([interval])
```
#### Parameters
- `interval`: slack time in milliseconds. Default: 2.
#### Returns
nil

## Lock()
A locking primative patterned after Python [Lock](https://docs.python.org/3/library/threading.html#threading.Lock). Note that, as with the Python version, Lock has no awareness of which thread or coroutine set the Lock. It will cheerfully wait forever if a thread acquires the Lock and then tries to acquire it again without a timeout and without exposing it to another process that might release it. It is safe to create a Lock instance from any context.

#### Syntax
```lua
local lock = Lock([locked])
```
#### Parameters
- `locked`: optional parameter that, if true, causes the Lock to be set when it is created.

#### Returns
The Lock instance.

## Lock.is_locked()
Tests the state of the Lock instance without changing it. This method is safe to call from any context.

#### Syntax
```lua
while lock:is_locked()
  --do something
  coroutine.yield()
end
```
#### Parameters
None
#### Returns
True if the Lock is set.

## Lock.await()
Waits for the Lock to be released with an optional timeout. This method does not itself change the state of the Lock. (See Lock.acquire().) This method should only be called from within a Task function.

#### Syntax
```lua
if not lock:await(timeout) then
  --handle timeout
end
--or
lock:await()
```
#### Parameters
- `timeout`: Optional number of seconds (may be fractional) to wait for lock to be released.

#### Returns
True if Lock is released, false if timeout occurred prior to the Lock being released.

## Lock.acquire()
Waits for the Lock to be released with an optional timeout, then sets the Lock. This method should only be called from within a Task function.

#### Syntax
```lua
if lock:acquire(timeout) then
  --do something with protected resource
  lock:release()
else
  --handle timeout
end
--or
lock:acquire()
--do something with protected resource
lock:release()
```
#### Parameters
- `timeout`: Optional number of seconds (may be fractional) to wait for the Lock to be released.

#### Returns
True if Lock was released, false if timeout occurred prior to the Lock being released.

## Lock.release()
Releases the lock. This method is safe to call from any context. For instance, it can be called from within a callback, which supports this kind of pattern:
```lua
--in Task function
  local done = Lock(true)
  local timeout = 10 --seconds
  do_something(...,function(result)
    --in callback
    done.result = result --if any
    done:release()
  end)
  if done:await(timeout) then
    --handle done.result
  else
    error("Timeout waiting for something to be done")
  end
```

#### Syntax
```lua
lock:release()
```
#### Parameters
None

#### Returns
nil

## Task()
Normally a Task instance is created by calling TaskQueue.schedule() which creates and returns a Task. A Task can also be constructed in any context by the syntax described below, but this is not recommended.

#### Syntax
```lua
task = Task(function(self, xxx, n)
  --do something
  coroutine.yield() -- yield to other Tasks
  --do more
  coroutine.yield(n) -- yield for at least 2.5 seconds
  --do more
end)
tq:schedule(5.5, task, 'xxx', 2.5) -- schedule task to start in 5.5 seconds with arguments xxx = 'xxx' and n = 2.5.
```
Note, this is not recommended. See TaskQueue.schedule() above for the recommended way.
#### Parameters
- `function`: The function to be dispatched by TaskQueue as a coroutine. When running under TaskQueue, the first parameter (self) on this function is its Task instance. Any other parameters on the tq:schedule() call are added to the function call after 'self'.

#### Returns
The Task instance.

## Task.final()
If present, this callback method is called by the TaskQueue dispatcher when a Task ends. Don't call this yourself. Only the dispatcher should call this. You may only call methods that are safe to call outside the context of a Task coroutine. Specifically, you may not call coroutine.yield() or any function that calls coroutine.yield() from within a task.final function.

#### Syntax
In the Task:
```lua
self.final = function(task, ok, msg, ...)
  --do something with when task ends
end
```
In the dispatcher when the Task ends:
```lua
pcall(task.final, task, ok, msg, ...)
```
#### Parameters
- `task`: The Task
- `ok`: The status returned by the most recent coroutine.resume(): true indicates that the Task ended normally.
- `msg`: The error message from the most recent resume if the Task threw an error (ok == false), nil otherwise.
- `...`: The variable arguments originally passed to the TaskQueue.schedule() method that created the Task.

#### Returns
N/A

## Task.stats()
Returns runtime statistics for the Task. This method is safe to call from any context.

#### Syntax
```lua
dispatches, time, maxtime = task:stats()
```
#### Parameters
None
#### Returns
- `dispatches`: Number of dispatches (resumes).
- `time`: Total time in microseconds that the Task was in the dispatched (running) state.
- `maxtime`: Maximum time in microseconds that the Task ran during a single dispatch.

## Task.await()
Waits for a Task to end with an optional timeout. (Same semantics as Lock.await()) This method should only be called from within a Task function other than the task being awaited.

#### Syntax
```lua
if not task:await(timeout) then
  --handle timeout
end
--or
task:await()
--do something after the task has ended
```
#### Parameters
- `timeout`: Optional number of seconds (may be fractional) to wait for the Task to end.

#### Returns
True if the Task ended, false if timeout occurred prior to the Task ending.

## Task.release()
Called by the dispatcher to signal that the Task has ended. Don't call this yourself. Only the dispatcher should call this.

#### Syntax
```lua
task:release()
```
#### Parameters
None

#### Returns
nil

## Task.is_active()
Returns true if the Task has not ended. This method is safe to call from any context.

#### Syntax
```lua
if task:is_active() then
  ...
end
```

#### Parameters
None

#### Returns
True if the Task is still active.
