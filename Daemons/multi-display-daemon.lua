--[[
    Multi-Display-Daemon
    This daemon provides functionality to assign multiple screens to multiple GPUs and mirror the content
    by intercepting 'component.invoke'. Additionally, the respective keybord gets selected automatically.
--]]


-- Files and Configurations
--

-- Libraries and components
local component = require("component");
local event = require("event");

local gpus = {};
local screens = {};
--

-- Variables and Constants
local component_invoke = component.invoke; --- Original method, for later restoring

local event_key_down = 0;
--

-- Data tables
-- 





--<< Daemon Functions >>--

function override_invoke()

    component.invoke = function(address, method, ...)

        local component_type = component.type( address );

        --- If invoked component is a gpu or screen, invoke method on all other gpus/screens that haven't been called directly as well.
        --- GPU that has actually been invoked gets called after all others. (See below return statement)
        if component_type == "gpu" then

            for i, gpu in pairs( gpus ) do

                if gpu.address ~= address then

                    component_invoke(gpu.address, method, ...);

                end

            end

        elseif component_type == "screen" then

            for i, screen in pairs( screens ) do

                if screen.address ~= address then

                    component_invoke(screen.address, method, ...);

                end

            end

        end


        return component_invoke(address, method, ...);

    end

end

--<< Daemon Functions end >>--




--<< RC Handling >>--

--- RC API start function - XXX
function start()

    for address, _ in pairs( component.list("screen") ) do

        local screen = component.proxy( address );

        screens[#screens + 1] = screen;

    end

    --- Iterate connected GPUs and bind a screen to each GPU
    for address, _ in pairs( component.list("gpu") ) do

        local gpu = component.proxy( address );

        gpus[#gpus + 1] = gpu;
        

        local screen = screens[ #gpus ];

        if screen then
            gpu.bind( screen.address );
        end

    end


    override_invoke();


    event_key_down = event.listen("key_down",
        function(_, keyboard)

            if not component.isPrimary( keyboard ) then

                component.setPrimary("keyboard", keyboard);

            end

            -- TODO: set this at every event? or add check??
            require("tty").window.keyboard = keyboard;


        end
    );

end

--- RC API stop function - XXX
function stop()

    component.invoke = component_invoke;

    event.cancel( event_key_down );

    screens = {};
    gpus = {};
    
end

--<< RC Handling >>--