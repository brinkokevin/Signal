local function createBatchedUpdate(fire: (self: any) -> ())
	local thread: thread? = nil

	return function()
		if thread then
			return
		end

		thread = task.defer(function()
			thread = nil
			fire()
		end)
	end
end

return createBatchedUpdate
