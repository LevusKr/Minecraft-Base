local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");

local gpu = term.gpu();


local width, height = term.getViewport();

local running = true;


term.setCursorBlink(false);


local function interrupt_handler()

    while running do

        term.pull("interrupted");
        running = false;
        
    end

end

local function input()

  while running do

    term.setCursor(1, height);
    term.write("> ");

    local inp = term.read({dobreak=false});

    term.clearLine();

    if inp == "cmd" or inp == "cmd\n" then

        term.write("> " .. inp .. "\n");
        term.write("cmd exec\n");

    end

  end

end

local function output()

    while running do

        term.setCursor(1, height - 1);
        term.write("test\n");
        term.scroll(1)
        term.setCursor(1, height);

        os.sleep(2)

    end

end

local function write(msg)

    

    term.write(msg);

end

local thread_input = thread.create(input)
local thread_output = thread.create(output)
local thread_interrupt = thread.create(interrupt_handler)



thread.waitForAll({thread_input, thread_output, thread_interrupt})

event.cancel(ev);