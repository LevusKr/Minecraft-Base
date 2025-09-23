local component = component;
local computer = computer;

local modem = component.proxy( component.list( "modem" )() );
local tunnel = component.proxy( component.list( "tunnel" )() );



local running = true;


while running do

    local event = { computer.pullSignal() };
    local event_data  = { table.unpack(event, 6) }; --- Pure payload, i.e. stripped 'modem_message' signal identifier

    if event[1] == "modem_message" then
        
        --- If incoming modem_message is received by modem, relay into linked channel OR vice versa
        if event[2] == modem.address then

            tunnel.send(event[3], event[4], table.unpack( event_data ));

        else

            modem.send(event_data[1], event_data[2], table.unpack(event_data, 3));

        end

    end

end