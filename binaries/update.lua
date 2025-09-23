local args = {...};

args = args[1] or {};

local download = args[1] or false;
local async = args[2] or false;
local timeout = args[3] or 10;

require("os").execute("rc update-daemon _update {download="..tostring(download)..",async="..tostring(async)..",timeout="..tostring(timeout).."}");