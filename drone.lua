local component = component;
local computer = computer;

local modem = component.proxy( component.list("modem")() );
modem.open(6000);
modem.setStrength(400);

local drone = component.proxy( component.list("drone")() );



local running = true;
local authenticated = false;

local key_local = "87q34wmh58";
drone.setStatusText( key_local );


while running do

    local event, _, sender, _, _, message, x, y, z  = computer.pullSignal();

    if event == "modem_message" then
        
        if not authenticated then

            if message == key_local then

                modem.send(sender, 6000, true, "Authenticated");
    
                drone.setStatusText("Authenticated");

                authenticated = true;
    
            else
    
                modem.send(sender, 6000, false, "Invalid key");
    
                drone.setStatusText("Invalid key");
    
            end

        else

            local result = { pcall(drone[ message ], x or 0, y or 0, z or 0) };

            modem.send(sender, 6000, result[1], table.unpack(result, 2));

        end

    end

end
