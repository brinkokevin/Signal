--!strict

-- The currently idle thread to run the next handler on
local freeRunnerThread: thread? = nil

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread(...)
	acquireRunnerThreadAndCallEventHandler(...)
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function spawnInFreeThread<T...>(fn, ...)
	if freeRunnerThread then
		task.spawn(freeRunnerThread, fn, ...)
	else
		local thread = coroutine.create(runEventHandlerInFreeThread)
		freeRunnerThread = thread
		task.spawn(thread, fn, ...)
	end
end

type InternalConnection<T...> = {
	connected: boolean,
	_fn: (T...) -> (),
	_next: InternalConnection<T...>?,
}

export type Connection = {
	disconnect: (self: any) -> (),
}

export type Signal<T...> = {
	fire: (self: Signal<T...>, T...) -> (),
	connect: (self: Signal<T...>, (T...) -> ()) -> Connection,
}

local function new<T...>(): Signal<T...>
	local connectionLinkedList: InternalConnection<T...>? = nil

	return {
		fire = function(_, ...: T...)
			while connectionLinkedList do
				if connectionLinkedList.connected then
					spawnInFreeThread(connectionLinkedList._fn, ...)
				end
				connectionLinkedList = connectionLinkedList._next
			end
		end,
		connect = function(_, fn: (T...) -> ())
			local connection: InternalConnection<T...> = {
				connected = true,
				_fn = fn,
				_next = nil,
			}

			if connectionLinkedList then
				connection._next = connectionLinkedList
				connectionLinkedList = connection
			else
				connectionLinkedList = connection
			end

			return {
				disconnect = function(_)
					if not connection.connected then
						return
					end
					connection.connected = false

					if connectionLinkedList == connection then
						connectionLinkedList = connection._next
					else
						local prev = connectionLinkedList
						while prev and prev._next ~= connection do
							prev = prev._next
						end
						if prev then
							prev._next = connection._next
						end
					end
				end,
			}
		end,
	}
end

return {
	new = new,
}
