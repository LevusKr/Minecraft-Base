--- @module 'cluster/future'
--[[
    Future
    This class provides functionality for creating futures, which executes
    a given task and calls handlers at success, failure and completion.
--]]


-- Libraries and components
local event = require("event");
local thread = require("thread");
--

-- Data tables
--- @class Future
--- 
--- @field task table {func=function, args=table}
--- @field handlers_success table
--- @field handlers_failure table
--- @field handlers_completion table
--- @field completed boolean
--- @field success boolean?
--- @field result any
local Future = {
    completed = false,
    success = nil,
    result = nil,
    finished = false
};
Future.__index = Future;
--




--<< Class Methods >>--

--- Instantiate a new future instance
function Future:create(func, ...)

    local future = setmetatable({

        task = {
            func = func,
            args = table.pack(...)
        },

        handlers_success = {},
        handlers_failure = {},
        handlers_completion = {}

    }, Future);


    return future;

end

--- Wrapper for executing task sync or async
function Future:run(async, ...)

    if async then

        thread.create(self.execute, self, ...);

    else

        self:execute(...);

    end


    return self;

end

--- Execute future's task and call handlers
function Future:execute(...)

    local execution_result = { pcall(self.task.func, table.unpack( ... == nil and self.task.args or {...} )) }; --- Call task function with task args given in future:create or this functions varargs
    local execution_success = execution_result[1]; --- Success of pcall

    local task_success, task_result = nil, nil; --- Success of task function and its return value(s)

    --- If pcall execution of task succeeded, evaluate return result containing task success and optional return value(s)
    if execution_success then

        task_success = execution_result[2]; --- Pcall execution succeeded ( execution_success = execution_result[1] ), task success follows next
        task_result = { table.unpack(execution_result, 3) }; --- Task execution succeeded, task success is pulled, remaining value(s) is/are task's return value(s)

    else

        task_success = false; --- Pcall execution failed, so task success is also false
        task_result = execution_result[2]; --- Pcall execution failed, so next (2nd) return value is pcall's error message instead of task's return value(s)

    end

    

    self.success = task_success;
    self.result = task_result;

    --- If there is only one task return value, unpack from wrapping table
    if #task_result <= 1 then

        self.result = task_result[1];

    end


    self.completed = true;



    --- Call success/failure handlers. 'task_result' will be task's return value(s) or pcall's error message
    for _, handler in ipairs( task_success and self.handlers_success or self.handlers_failure ) do

        self:call_handler( handler );

    end

    --- Call completion handlers. 'task_result' and 'task_success' will be whether task succeeded or not (see handler call above)
    for _, handler in ipairs( self.handlers_completion ) do

        self:call_handler( handler );

    end

    self.finished = true;


    return self.success, self.result;

end

--- Wait for future's task to complete. 'finish' triggers await until all registered handlers are called
function Future:await(finish)

    repeat

        os.sleep(0.05);

    until (finish and self.finished or self.completed)


    return self;

end

--- Internal function for calling given handler.
function Future:call_handler(handler, ...)

    checkArg(1, handler, "function");

    local args = {...};


    local handler_success, handler_result = xpcall(
        handler,
        debug.traceback,
        (
            #args > 0
            and table.unpack( args )
            or self.result
        )
    );


    if not handler_success then

        event.onError("Error in future's handler: " .. tostring( handler_result )); -- TODO: add some kind of id to handler's for easier traceback/debug

    end

end


--- Add handler of given type to appropriate handler list. Valid types are 'success', 'failure' and 'completion'
function Future:on_handler(handler, type)

    local list_handlers = {};
    local call = false; --- Whether it is appropriate to immediatly call this handler when future already finished and called previously registered handlers

    if type == "success" then

        list_handlers = self.handlers_success;

        if self.success then
            call = true;
        end

    elseif type == "failure" then

        list_handlers = self.handlers_failure;

        if not self.success then
            call = true;
        end

    elseif type == "completion" then

        list_handlers = self.handlers_completion;

        if self.completed then
            call = true;
        end

    end


    --- If future already completed, handlers have already been called, so directly call new handler here. Otherwise just add handler to list
    if self.completed and call then

        self:call_handler( handler );

    else

        table.insert(list_handlers, handler);

    end



    return self;

end

--- Add handler for when task succeeded
function Future:on_success(handler)

    return self:on_handler(handler, "success");

end

--- Add handler for when task has failed
function Future:on_failure(handler)
    
    return self:on_handler(handler, "failure");

end

--- Add handler for when task is completed
function Future:on_completion(handler)
    
    return self:on_handler(handler, "completion");

end

--<< Class Methods end >>--




--- Return class object
return Future;