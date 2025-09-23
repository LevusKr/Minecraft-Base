--[[
    Utils
    Collection of utilities sorted by category.
    Including global constants, functions, function wrappers, etc.
--]]


-- Libraries and components
local component = require("component");
local computer = require("computer");
local event = require("event");
local filesystem = require("filesystem");
local os = require("os");
local serialization = require("serialization");
local term = require("term");

local gpu = component.gpu;
local modem = component.modem;
local data = component.data;
--


-- API tables
local utils = {};
  constants = {};
  utils.encoding = {};
  utils.file = {};
  utils.config = {};
  utils.internal = {};
  utils.time = {};
  utils.math = {};
  utils.format = {};
  utils.table = {};
  utils.event = {};
  utils.logging = {};
  utils.graphic = {};
  utils.network = {};
--


-- Constants
--



-- Functions according encoding
--


-- Functions according files
function utils.file.read(path, binary)
  if not filesystem.exists(path) then return nil; end -- if file does not exist, return nil

  local file = io.open(path, "r"..(binary and "b" or ""));
  local data = {}
  if file then
    data = file:read("*a");
  end
  
  file:close();
  return data;
end

function utils.file.write(path, data, append, binary)
  local file = type(path) == "string" and assert(io.open(path, (append and "a" or "w")..(binary and "b" or ""))) or path; -- open file in write or append mode. additionally binary
  if file then
    file:write(data);
    if type(path) == "string" then
      file:close();
    end
    return true;
  end

  return false;
end

function utils.file.minify(file, decode) -- minifies file (e.g. for networking)
  if type(file) == "string" then -- path
    local content = decode and utils.config.load(file) or utils.file.read(file, true);
    if content then
      return content:gsub(" ", "");
    end
  elseif type(file) == "table" then -- table holding multiple paths
    for _, _file in ipairs(file) do
      return utils.file.minify(_file);
    end
  end

  return file;
end
--


-- Functions according configs
--


-- Functions according internals
function utils.internal.hostname()
  local hostname = utils.file.read("/etc/hostname");
  if not hostname then
    hostname = "host-"..math.random(1, 100);
    utils.file.write("/etc/hostname", hostname);
  end

  return hostname;
end

function utils.internal.updates() -- file holding list of updateable files
  local updates = utils.config.load("/etc/updates.cfg");
  if not updates then
    updates = {};
    utils.config.save("/etc/updates.cfg", updates);
  end

  return updates;
end

function utils.internal.custom(path) -- custom system config
  local custom = utils.config.load(path);
  if not custom then
    custom = {};
    utils.config.save(path, custom);
  end

  return custom;
end
--


-- Functions according time
function utils.time.format()
  return os.date("%T");
end

function utils.time.format_seconds(seconds, no_decimals)

    if seconds > 290304000 then

        return "10 years+";

    elseif seconds >= 29030400 then

        return tostring(string.format("%.1f", seconds/29030400)) .. " year(s)";

    elseif seconds >= 2419200 then

        return tostring(string.format("%.1f", seconds/2419200)) .. " month(s)";

    elseif seconds >= 604800 then

        return tostring(string.format("%.1f", seconds/604800)) .. " week(s)";

    elseif seconds >= 86400 then

        return tostring(string.format("%.1f", seconds/86400)) .. " day(s)";

    elseif seconds >= 3600 then

        return tostring(string.format("%.1f", seconds/3600)) .. " hour(s)";

    elseif seconds >= 60 then

        return tostring(string.format("%.1f", seconds/60)) .. " minute(s)";

    else

        return tostring(string.format("%.2f", seconds)) .. " second(s)";

    end

end
--

-- Functions according math
function utils.math.round(value, precision)
  precision = precision or 1;

  return math.floor(value + 5*10^-precision);
end

function utils.math.even(value)
  return ((value % 2 == 1) and (value + 1) or value);
end

function utils.math.odd(value)
  return utils.math.round((value % 2 == 0) and (value + 1) or value);
end

function utils.math.adjust_value(value, unit, fine)
  if value >= 1000000000000000 then
    return tostring(string.format("%.2f", value/1000000000000000)) .. " P" .. unit; --- Peta
  elseif value >= 1000000000000 then
    return tostring(string.format("%.2f", value/1000000000000)) .. " T" .. unit; --- Tera
  elseif value >= 1000000000 then
    return tostring(string.format("%.2f", value/1000000000)) .. " G" .. unit; --- Giga
  elseif value >= 1000000 then
    return tostring(string.format("%.2f", value/1000000)) .. " M" .. unit; --- Mega
  elseif value >= 1000 then
    return tostring(string.format("%.2f", value/1000)) .. " k" .. unit; --- Kilo
  elseif value < 0.01 then
    return tostring(string.format("%.2f", value/0.001)) .. " m" .. unit; --- Milli
  elseif value < 0.1 and fine then
    return tostring(string.format("%.2f", value/0.01)) .. " c" .. unit; --- Centi
  elseif value < 1 and fine then
    return tostring(string.format("%.2f", value/0.1)) .. " d" .. unit; --- Deci
  else
    return tostring(string.format("%.2f", value)) .. " " .. unit; --- Base
  end
end
--


-- Functions according formats
function utils.format.tuple(value)
    
    return value ~= nil, value;
    
end
--


-- Functions according tables
function utils.table.remove_overflow(_table, maximum) -- removes all entries above given index from given table
  local size = #_table;
  if size <= maximum then return _table; end

  repeat
    table.remove(_table, maximum+1);
    size = size-1;
  until size == maximum
end
--


-- Functions according events
--


-- Functions according logging
--


-- Functions according networking
--



-- Return table with functions
return utils;