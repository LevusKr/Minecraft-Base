--[[
    Config
    This class provides functionality for creating configs, which represent
    a file on disk and reads/writes data to it.
--]]


-- Libraries and components
local codec = require("cluster/codec");
--

-- Data tables
--- @module 'cluster/config'
--- @class Config
---
--- @field path string?
--- @field file file*? OpenOS file handle
--- @field contents table?
local Config = {
    path = nil,
    file = nil,
    contents = nil
};
Config.__index = Config;
--




--<< Class Methods >>--

--- Instantiate new config pointing to specified path, along with an (additional) default set of values
function Config:create(path, default)

    local config = setmetatable({
        path = path,
        contents = default or {}
    }, Config);


    return config;

end

--- Attempts to open file at given path and read contents into table
function Config:open(mode)

    if self.file then

        self.file:close();

    end


    local file, error = io.open(self.path, mode);

    self.file = file;


    return file or error;

end

--- Returns whether file is currently open
function Config:is_open()

    return self.file ~= nil;

end

--- Attempts to open file at given path and read contents into table
function Config:load(options)

    options = options or {};


    local result_open = self:open("r");

    if not self:is_open() then

        return false, result_open;

    end


    self.contents = codec.decode( self.file:read("*a") );


    if not options.keep_open then

        self.file:close();

    end


    return true, self.contents;

end

--- Attempts to write current contents into file at given path. Optionally keeps file handle open
function Config:save(options)

    options = options or {};


    local result_open = self:open("w");

    if not self:is_open() then

        return false, result_open;

    end


    self.file:write( codec.encode( self.contents ) );
    self.file:flush();


    if not options.keep_open then

        self.file:close();

    end


    return true, self;

end

--- Retrieves the key's associated value. Optionally (re-)loads config before
function Config:get(key, options)

    options = options or {};


    if options.reload then

        self:load();

    end

    return self.contents[ key ];

end

--- Updates the key's associated value. Optionally (re-)loads config before
function Config:set(key, value, options)

    options = options or {};


    if options.reload then
        self:load();
    end


    local value_old = self:get( key );
    
    self.contents[ key ] = value;


    return value_old;

end

--- Retrieves full list of content. Optionally (re-)loads config before
function Config:content(options)

    options = options or {};


    if options.reload then

        self:load();

    end

    return self.contents;

end

--<< Class Methods end >>--




--- Return class object
return Config;