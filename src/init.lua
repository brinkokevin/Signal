local spawnInFreeThread = require(script.spawnInFreeThread)
local createBatchedUpdate = require(script.createBatchedUpdate)

type InternalConnection<T...> = {
	connected: boolean,
	_fn: (T...) -> (),
	_next: InternalConnection<T...>?,
}

export type Connection = {
	disconnect: (self: any) -> (),
}

export type Signal<T...> = {
	fire: (T...) -> (),
	connect: ((T...) -> ()) -> Connection,
}

local function new<T...>()
	local connectionLinkedList: InternalConnection<T...>? = nil

	return {
		fire = function(...: T...)
			local tempLinkedList = connectionLinkedList
			while tempLinkedList do
				if tempLinkedList.connected then
					spawnInFreeThread(tempLinkedList._fn, ...)
				end
				tempLinkedList = tempLinkedList._next
			end
		end,
		connect = function(fn: (T...) -> ()): Connection
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
	createBatchedUpdate = createBatchedUpdate,
}
