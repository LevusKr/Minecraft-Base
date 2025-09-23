--[[
    Event-Library
    This library provides enhanced functionality for event handling,
    such as async filtering and timeout or handling callback functions.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local Future = require("cluster/future");

local computer = require("computer")
local _event = require("event");
--

-- Data tables
--- @module 'cluster/event'
local event = {};
--




--<< API Methods >>--

--- Waits infinitely or timeout duration for specified event to occur and if the (optional) filter allows so, returns event data (blocking)
--- 
--- @param task string|function Either event name or filter function
--- @param timeout? number Timeout in seconds
--- @vararg any Expected event return value(s) in order of the event's return signature
--- 
--- @return boolean success
--- @return string|any? ... Error string or event return value(s)
function event.await(task, timeout, ...)

    if type(task) == "string" then --- Event name

        local deadline = computer.uptime() + (timeout or 5);
        local event_data = {};
        repeat

            event_data = { _event.pull(0.05, task, ...) };

        until #event_data ~= 0 or computer.uptime() >= deadline


        local success = event_data[1] ~= nil;
        local result =
            success
            and { table.unpack(event_data, 2) }
            or "Timed out"
        ;


        if type( result ) == "table" then

            return success, table.unpack( result );

        else

            return success, result;
            
        end

    elseif type(task) == "function" then --- Filter function

        local deadline = computer.uptime() + (timeout or 5);
        local event_data = {};
        repeat

            event_data = { _event.pullFiltered(0.05, task) };

        until #event_data ~= 0 or computer.uptime() >= deadline


        local success = event_data[1] ~= nil;
        local result =
                    success
                    and { table.unpack(event_data, 2) }
                    or "Timed out"
        ;

        
        if type( result ) == "table" then

            return success, table.unpack( result );

        else

            return success, result;
            
        end

    else

        error("Type of task has to be string or function");

    end
    
end

--- Listens in background infinitely or timeout duration for specified event to occur and if
--- the (optional) filter allows so, calls callback function with event data (non-blocking)
--- @async
--- 
--- @param name string
--- @param callback function
--- @param filter? function
--- @param timeout? number Timeout duration in seconds
--- 
--- @return number id_listener OpenOS event id for referencing and/or cancelling
function event.await_async(name, callback, filter, timeout)

    local helper = function(...)

        if filter then --- Filter present?

            if filter(...) then --- Filter allows this event?

                xpcall(callback, _event.onError, ...); --- Notify callback!

            end

        else --- Nope, just notify callback...

            xpcall(callback, _event.onError, ...); --- ...duh.

        end

        return false; --- This way the base event api automatically ignores/forgets function after completion

    end



    local id_listener = _event.listen(name, helper); --- Return event id for referencing and/or cancelling

    _event.timer(timeout or 5,

        function()
            if _event.cancel(id_listener) then --- Cancels listener and returns whether it was still listening at cancellation.
                xpcall(callback, _event.onError); --- If it was still listening, is hasn't been called a single time, so call it with no arguments once.
            end
        end

    , 1);


    return id_listener;

end

--- Wraps task awaiting as future, either sync or asynchronous
function event.await_future(task, async, timeout)

    return Future:create(
        event.await,
        task,
        timeout
    ):run( async );

end

--- Returns function filtering by given event name and comparing first event argument to specified comparand
function event.filter_first(name, comparand)

    return
        function(_name, first_argument)
            return (_name == name) and (first_argument == comparand);
        end
    ;

end


--- Pushes an event in the queue along with (encoded) event data 
function event.push(name, encode, ...)
    local payload = {...};

    if encode then
        payload = codec.encode(payload);
    end


    _event.push(name, payload);
end

--- Pushes an event in the queue along with encoded event data 
function event.push_encoded(name, ...)
    event.push(name, true, ...);
end

--<< API Methods end >>--




--- Return API Methods as table
return event;