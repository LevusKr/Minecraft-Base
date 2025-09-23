--- @module 'cluster/terminal'
--[[
    Logger
    This class provides functionality for creating terminals on top of the OpenOS term-api and cluster/logger.
    A Terminal wraps
--]]


-- Libraries and components
-- local codec = require("cluster/codec");
local component = require("component");
local term = require("term");
--

-- Data tables
--- @class Terminal
--- 
--- @field name string
--- @field width number
--- @field height number
--- @field input_x number
--- @field input_y number
--- @field last_print_y number
--- @field logger Logger?
--- @field log_func function?
local Terminal = {
    name = "terminal",

    width = 0,
    height = 0,
    input_x = 1,
    input_y = 0,

    last_print_y = 0,

    logger = nil,
    log_func = nil
};
Terminal.__index = Terminal;

Terminal.width, Terminal.height = term.getViewport();
Terminal.height = Terminal.height - 1;
Terminal.input_y = Terminal.height;
--





--<< Class Methods >>--

function Terminal.create(name, logger, width, height, input_x, input_y)

    local terminal = setmetatable({
        name = name,

        width = width,
        height = height,
        input_x = input_x,
        input_y = input_y,

        last_print_y = 0,

        log_func = logger.log
    }, Terminal);



    logger.log = function(_logger, level, message, print)

        --- This logic prevents the terminal from formatting and scrolling as if a log entry has been printed, when the printing was actually disabled
        if (level == "debug" and not _logger.print_debug)
            or (level == "verbose" and not _logger.print_verbose) then

            --- Calls original Logger#log function
            return terminal.log_func(_logger, level, message, print);

        end

        --- Calls terminal's write function, which eventually calls Logger#log
        return terminal:write(_logger, level, message, print);

    end


    term.clear();
    term.setCursorBlink(true);
    terminal:redraw_input_line();



    return terminal;

end

function Terminal:close(logger)

    logger.log = self.log_func;

end


-- Funktion, um die Eingabezeile neu zu zeichnen
function Terminal:redraw_input_line(clear)
    
    term.setCursor(self.input_x, self.input_y)

    if clear then
        term.clearLine()
    end
    
    term.write(self.name .. " > ")

end

function Terminal:clear()

    term.clear();
    self.last_print_y = 0;
    self:redraw_input_line();

end

function Terminal:read(options, tab_completer)

    options.nowrap = false;
    options.dobreak = false;
    options.hint = tab_completer;

    local input = term.read(
        options,
        _,
        _,
        _,
        _,
        true
    );

    --- Removes trailing new-line char (\n)
    return input;

end

-- Funktion, um Ausgaben zu printen, ohne die Eingabezeile zu stören
function Terminal:write(logger, level, message, print)

    if not message then message = "nil" end;

    -- component.gpu.setBackground(0x000000)
    -- component.gpu.setForeground(0xFFFFFF)

    term.setViewport(self.width, self.input_y - 1);


    if self.last_print_y < (self.input_y - 1) then

        term.setCursor(1, self.last_print_y + 1)

        local _, num_nl = message:gsub("\n", "");

        self.last_print_y = self.last_print_y + 1 + num_nl;

    else

        -- TODO: apparently, something leads to the terminal automatically scrolling down (text goes up) when the second-last line has been written. what the fuck
        term.scroll(0)
        term.setCursor(1, self.input_y - 1);

    end


    if logger then

        self.log_func(logger, level, message, print);

    else

        term.write( message );

    end


    term.setViewport(self.width, self.height);

    self:redraw_input_line();

end





return Terminal;