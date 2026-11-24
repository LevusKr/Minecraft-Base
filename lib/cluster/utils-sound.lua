--[[
    Sound-Utils-Library
    This library provides enhanced functionality for sounds,
    such as composing, XXX and manipulating.
--]]


-- Libraries and components
local utils = require("cluster/utils");
local constants = require("cluster/constants");

local computer = require("computer");
--

-- Data tables
local utils_sounds = {};
--




--<< API Methods >>--

--- 
function utils_sounds.const(type)

    if (constants.sound.success) then
        
        computer.beep(2000, 0.05);

    elseif (constants.sound.failure) then

        computer.beep(200, 0.05);
        computer.beep(200, 0.05);
        computer.beep(200, 0.05);

    elseif (constants.sound.info) then

        computer.beep(1000, 0.05);
        computer.beep(1000, 0.05);

    elseif (constants.sound.warning) then

        computer.beep(500, 0.05);
        computer.beep(500, 0.05);

    elseif (constants.sound.severe) then

        computer.beep(200, 0.05);
        computer.beep(200, 0.05);
        computer.beep(200, 0.05);

    elseif (constants.sound.error) then

        computer.beep(200, 0.05);
        computer.beep(200, 0.05);
        computer.beep(200, 0.05);
        computer.beep(200, 0.05);
        computer.beep(200, 0.05);

    end

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_sounds;