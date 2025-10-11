--[[
    Graphics-Library
    Collection of graphical utilities.
    Including global constants, functions, function wrappers, etc.

        TODO:
            - change positioned parameters to named parameters via table, this allows dynamic usage of parameters/element's functions
                element(x, y, width, height, ...)  -->  element( {x = 1, y = 1, width = 100, height = 100, ... = ...} )
            
            - store children more accessable
            - double buffering
--]]


-- Libraries and components
local colors = require("cluster/colors-hex");
local utils = require("cluster/utils");

local component = require("component");
local event = require("event");


local gpu = component.gpu;
--

-- Data tables
local Element = {
    x = 0,
    y = 0,
    width = 0,
    height = 0,
    border = 0,
    border_label = "",
    label = "",

    color_background = 0x2D2D2D,
    color_border = 0x3C3C3C,
    color_border_background = 0x0,
    color_border_label = 0xFFFFFF,
    color_label = 0xFFFFFF,

    visible = true
};
Element.__index = Element;


local graphics = {};
--




--<< API Methods >>--

--- Registers listeners etc. and calls initial create function
function Element:init()

    self.listeners_event = self.listeners_event or {};



    local function touch(...)

        local event_data = {...};
        local _event, x_pressed, y_pressed, button, user = event_data[1], event_data[3], event_data[4], event_data[5], event_data[6];

        self:touch(_event, x_pressed, y_pressed, button, user);

    end


    event.listen("touch", touch);

    self.listeners_event[ #self.listeners_event + 1 ] = {
        key = "touch",
        listener = touch
    };


    event.listen("drag", touch);

    self.listeners_event[ #self.listeners_event + 1 ] = {
        key = "drag",
        listener = touch
    };


    event.listen("drop", touch);

    self.listeners_event[ #self.listeners_event + 1 ] = {
        key = "drop",
        listener = touch
    };



    self:create();

end

--- Inital function to build element tree and draw it on screen once, for later redrawing use Element:redraw()
function Element:create()

    --- If element has parent object, make coordinates relative to parent
    if self.parent then

        self.x = (self.parent.x + self.x - 1);
        self.y = (self.parent.y + self.y - 1);

    end


    --- If border is enabled, draw it
    if self.border and self.border > 0 then

        local element_border = graphics.draw_border(
            0,
            0,
            self.width + 2,
            self.height + 2,
            self.border_label,
            self.color_border,
            self.color_border_background,
            self.color_border_label
        );

        self:child_add( element_border );

        -- TODO: remove
        self.child_border = element_border;

    end


    self:draw( true );

end

--- Initial function to end element execution in terms of event handling etc.
--- Since redrawing is *usually* done by these elements, actually their event handlers, themselves, that will be stopped. (i.e. doesn't affect user-sided element processing, this has to be stopped along with calling this function)
function Element:destroy()

    for _, entry in pairs( self.listeners_event or {} ) do

        event.ignore(entry.key, entry.listener);

    end

    if self.children then

        for i, child in pairs( self.children ) do

            self.children[ i ] = nil;
            child.parent = nil;

            child:destroy();

        end

    end

    if self.parent then

        self.parent:child_remove( self );

    end

    -- TODO: call element specific kill function AND should there be a children's kill function???

end

--- Draws element tree to screen. Optionally force creation via 'create' parameter
function Element:draw(create, redraw)

    local parent = self.parent;

    --- Set visibility to whether parent is visible. When parent is currently being dragged, turn invisible
    if parent then

        local parent_drag_active = parent.drag and parent.drag.active;
        local drag_active = self.drag and self.drag.active;

        --- If parent is currently being dragged, turn invisible, else adapt parent's visibility. Element's direct Borders never turn invisible while dragging
        if parent_drag_active then

            --- Set visibilty to 'false' when parent is dragged;   If this is the border of the dragged element to 'true'
            self.visible =
                self == parent.child_border
                and true
                or false
            ;

        elseif drag_active then

            self.visible = self.visible;

        else

            -- TODO: this doesn't allow child elements to be invisible on their own
            if self.visible_excl ~= nil then

                self.visible = self.visible_excl;

            else

                self.visible = parent.visible;

            end

        end

    end


    --- If self is no Border element, draw background rectangle. This prevents drawing a rectangle over a border's parent element since children (here: border) are drawn after parents
    if self.visible and (self.type ~= "Border") and (self.type ~= "Vertical Histogram") then

        if redraw then

            gpu.setBackground( 0x0 );
            gpu.fill(self.x - 1, self.y - 1, self.width + 2, self.height + 2, " ");

        end

        gpu.setBackground( self.color_background );
        gpu.fill(self.x, self.y, self.width, self.height, " ");

    end



    if self.visible then

        --- Draws element-specific stuff
        self:paint();

    end


    --- Create children elements
    if self.children then

        for _, child in pairs( self.children ) do

            if create then

                child:create();

            else

                child:draw();

            end

        end

    end

end

--- Alias method for Element:draw
function Element:redraw(clear)

    self:draw(false, clear);

end

--- Adds given element as child. Optionally redraws self and all descending elements
function Element:child_add(child, redraw)

    self.children = self.children or {};
  
    self.children[ #self.children + 1 ] = child;
    child.parent = self;


    if redraw then

        self:redraw();

    end

end

--- Removes given element as child. Optionally redraws self and all descending elements
function Element:child_remove(child, redraw)

    for i, _child in pairs( self.children ) do

        if child == _child then

            self.children[ i ] = nil;
            goto after;

        end

    end

    ::after::

    child.parent = nil;


    if redraw then

        self:redraw();

    end

end


--- Hands touch signal down the element tree, with every element at touched coordinates calling element specific function
function Element:touch(_event, x_pressed, y_pressed, button, user)

    -- if self.type == "Container" then event.onError(_event .. " " .. tostring(self)) end

    if self.call then

        --- Ignore boundaries while ongoing drag, so call it's specific callback
        if self.drag and self.drag.active then

            self:call(_event, x_pressed, y_pressed, button, user);

        else

            if self.visible then

                local x, y, width, height = self.x, self.y, self.width, self.height;

                --- If border is present, it sits 1px around an element, thus effectively making the element bigger than it's internal constraints 
                if self.border then

                    x = x - 1;
                    y = y - 1;
                    width = width + 2;
                    height = height + 2;

                end

                --- Inside element's width boundaries
                if (x <= x_pressed) and (x_pressed < x + width) then

                    --- Inside elements' height boundaries
                    if (y <= y_pressed) and (y_pressed < y + height) then

                        self:call(_event, x_pressed, y_pressed, button, user); -- Inside boundaries (+ border), so call it's specific callback

                    end

                end

            end

        end

    end


    --- If element has children, call this method for them to handle touch event aswell
    if self.children then

        for _, child in pairs( self.children ) do

            child:touch(_event, x_pressed, y_pressed, button, user);

        end

    end

end



--- Justifies text to x- and y-center. Returns x, y and given text for passing it directly into gpu.set(x, y, text)
function graphics.justify(x, y, width, height, text)
    return (( width / 2 ) - ( text:len() / 2 )) + x,
        height / 2 + y,
        text
        ;
end

function graphics.justify_x(x, y, width, text)
    return (( width / 2 ) - ( text:len() / 2 )) + x,
        y,
        text
    ;
end

function graphics.justify_y(x, y, height, text)
    return x,
        height / 2 + y,
        text
    ;
end

function graphics.draw_line(x, y, length)
    
    gpu.fill(
        x or 0,
        y or 0,
        length or select(1, gpu.getResolution()),
        1,
        "-"
    );

end

--- Returns a border of 0.5-2 thickness along with an (additional) label around the given rectangle.
--- color_background is only relevant for .5 borders since they use half pixels and the other empty half is just the screen background, therefore colored in the gpu's background color.
--- Usually this is set to the sorrounding background color of the empty screen. (default 0x0)
function graphics.draw_border(x, y, width, height, label, color, color_background, color_label)

    local border = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        label = label,

        color = color,
        color_background = color_background,
        color_label = color_label,

        type = "Border"
    }, Element);



    border.paint = function(self)

        gpu.setBackground(self.color_background);
        gpu.setForeground(self.color);

        gpu.set(self.x, self.y, (self.label and "▐" or "▗")); --- top left corner
        gpu.set(self.x + 1, self.y, string.rep(("▄"), self.width - 2)); --- top row
        gpu.set(self.x + self.width - 1, self.y, (self.label and "▌" or "▖")); --- top right corner

        gpu.set(self.x, self.y + 1, string.rep("▐", self.height - 2), true); --- left column
        gpu.set(self.x + self.width - 1, self.y + 1, string.rep("▌", self.height - 2), true); --- right column

        gpu.set(self.x, self.y + self.height - 1, "▝"); --- bottom left corner
        gpu.set(self.x + 1, self.y + self.height - 1, string.rep("▀", self.width - 1)); --- bottom row
        gpu.set(self.x + self.width - 1, self.y + self.height - 1, "▘"); --- bottom right corner


        self.children[1].text = self.label;
        self.children[1].color_label = self.color_label;

    end



    if label then

        local element_label = graphics.label(
            2,
            1,
            width - 2,
            1,
            label,
            color,
            color_label
        );

        border:child_add( element_label );


        border.child_label = element_label;

    end




    return border;

end

--- Returns a container (optionally with border and label) for managing multiple child elements at once, so w/o children this is effectively just a colored square on the screen
function graphics.container(x, y, width, height, border, border_label, color_background, color_border, color_border_background, color_border_label)

    local container = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),
        border = border,
        border_label = border_label,

        color_background = color_background,
        color_border = color_border,
        color_border_background = color_border_background,
        color_border_label = color_border_label,

        type = "Container",

        drag = {
            active = false,
            x_start = x,
            y_start = y,
            x_current = x,
            y_current = y
        }
    }, Element);



    container.call = function(self, _event, x_pressed, y_pressed, button)

        if _event == "touch" then

            --- Only allow dragging at top bar. Will be off by one px if a border sorrounds this container
            local y_top =
                self.border
                and (self.y - 1)
                or self.y
            ;

            --- If touch is at top bar and container is visible, activate drag
            if (y_pressed == y_top) and self.visible then

                self.drag = {
                    active = true,
                    x_start = x_pressed,
                    y_start = y_pressed,
                    x_current = x_pressed,
                    y_current = y_pressed
                };


                --- If container has a border, turn invisible but keep border visible (see Element.draw)
                if self.border then

                    self.visible = false;

                end

                gpu.setBackground(0x0);
                gpu.fill(self.x, self.y, self.width, self.height, " ");

            end

        elseif _event == "drag" then

            --- If container is currently being dragged (see above)
            if self.drag.active then

                --- Last pressed position
                local x_pressed_last = self.drag.x_current;
                local y_pressed_last = self.drag.y_current;

                --- Current (new) pressed position
                self.drag.x_current = x_pressed;
                self.drag.y_current = y_pressed;


                --- Difference between positions
                local x_difference = x_pressed - x_pressed_last;
                local y_difference = y_pressed - y_pressed_last;


                --- Last container position
                local x_last = self.x;
                local y_last = self.y;


                --- If border is present, update it's position for easier eye-tracking while dragging and redraw container later on when drag is finished
                local child_border = self.child_border;

                if child_border then

                    child_border.x = child_border.x + x_difference;
                    child_border.y = child_border.y + y_difference;

                    if child_border.child_label then

                        child_border.child_label.x = child_border.child_label.x + x_difference;
                        child_border.child_label.y = child_border.child_label.y + y_difference;

                    end

                else --- Else, update container directly

                    --- Current (new) container position
                    self.x = self.x + x_difference;
                    self.y = self.y + y_difference;

                end


                gpu.setBackground( 0xF );

                --- Clear screen part that the container has revealed
                if x_difference > 0 then

                    if child_border then

                        gpu.fill(child_border.x - 1, child_border.y, x_difference, child_border.height, " ");

                    else

                        gpu.fill(x_last, y_last, x_difference, self.height, " ");

                    end

                elseif x_difference < 0 then

                    if child_border then

                        gpu.fill((child_border.x) + child_border.width + x_difference, child_border.y, x_difference * -1, child_border.height, " ");

                    else

                        gpu.fill(x_last + self.width + x_difference, y_last, x_difference * -1, self.height, " ");

                    end

                end

                if y_difference > 0 then

                    if child_border then

                        gpu.fill(child_border.x, child_border.y - 1, child_border.width, y_difference, " ");

                    else

                        gpu.fill(x_last, y_last, self.width, y_difference, " ");

                    end

                elseif y_difference < 0 then

                    if child_border then

                        gpu.fill(child_border.x, (child_border.y) + child_border.height + y_difference, child_border.width, y_difference * -1, " ");

                    else

                        gpu.fill(x_last, y_last + self.height + y_difference, self.width, y_difference * -1, " ");

                    end

                end


                child_border:redraw();

            end

        elseif _event == "drop" then

            --- If container is currently being dragged (see above)
            if self.drag.active then

                local x_start, y_start = self.drag.x_start, self.drag.y_start;

                local x_difference = x_pressed - x_start;
                local y_difference = y_pressed - y_start;

                if (x_difference == 0) and (y_difference == 0) then

                    return;

                end


                --- If border is present, update container's position now (see touch event above)
                if self.border then

                    self.x = self.x + x_difference;
                    self.y = self.y + y_difference;

                end


                local element_border = self.child_border;
                local element_border_label = element_border.child_label;

                --- Update children's position
                local function update_children(element)

                    for i, child in pairs( element.children ) do

                        --- Update every child's position except container's border since it's updated live already (see above)
                        if child ~= element_border and child ~= element_border_label then

                            child.x = child.x + x_difference;
                            child.y = child.y + y_difference;

                        end


                        --- Recursive
                        if child.children then

                            update_children( child );

                        end

                    end

                end

                update_children( self );


                self.drag.active = false;

                self.visible = true;

                self:redraw();

            end

        end

    end



    container.paint = function(self)

        -- TODO: do container paint specific stuff

    end
    



    return container;

end

--- Returns a label inside a box of given boundaries with given background color. Alignment specifies placement of text inside said box.
--- Available alignments are LEFT, RIGHT and CENTERED, whereas combining with _TOP or _BOTTOM aligns them vertically (leaving this out is centered vertically).
--- Examples would be LEFT, CENTERED_BOTTOM, RIGHT_TOP etc.
function graphics.label(x, y, width, height, text, color_background, color_label, alignment, alignment_vertical, options)

    options = options or {};

    local label = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),
        text = text,

        color_label = color_label,
        color_background = color_background,

        alignment = alignment or "CENTER",
        alignment_vertical = alignment_vertical or "CENTER",

        type = "Label",

        popup = options.popup,
        data = options.data
    }, Element);



    --- If label is clicked, show popup with full data (e.g. long version of text, description etc.)
    label.call = function(self, _event, x_pressed, y_pressed, button)

        if _event == "touch" and self.popup then

            if not self.child_popup then

                event.onError("no popup child present")

                local res_x, res_y = gpu.getResolution();

                local container_popup = graphics.container(
                    (-self.x) + res_x / 4,
                    (-self.y) + res_y / 4,
                    res_x / 2,
                    res_y / 2,
                    1,
                    "LABEL DESC",
                    self.color_background,
                    colors.border,
                    colors.black,
                    self.color_label
                );

                self:child_add( container_popup );

                self.child_popup = #self.children;

                event.onError("popup child created: " .. tostring(self.child_popup))

                container_popup:init();

                container_popup.visible_excl = true;

            else

                event.onError("popup child present")

                local child_popup = (self.children or {})[ self.child_popup ];
                event.onError("popup child existing?: " .. tostring(child_popup))

                if child_popup then

                    event.onError("popup child existing?: " .. tostring(child_popup.visible_excl))

                    child_popup.visible_excl = not child_popup.visible_excl;

                end

            end

        elseif _event == "drop" and self.child_popup then

            (self.children or {})[ self.child_popup ].visible_excl = false;

        end

    end



    label.paint = function(self)

        gpu.setBackground(self.color_background);
        gpu.setForeground(self.color_label);

        local index = 0;
        for line in self.text:gmatch("([^\n]+)") do

            local x_aligned = self.x;

            if self.alignment == "LEFT" then

                x_aligned = self.x;

            elseif self.alignment == "RIGHT" then

                x_aligned = x_aligned + (self.width - #line:sub(1, self.width));

            else --- CENTER

                x_aligned = x_aligned + (self.width / 2  -  #line:sub(1, self.width) / 2);

            end


            local y_aligned = self.y;

            if self.alignment_vertical == "TOP" then

                y_aligned = self.y;

            elseif self.alignment_vertical == "BOTTOM" then

                y_aligned = y_aligned + (self.height - 1);

            else --- CENTER

                y_aligned = y_aligned + ((self.height - 1) / 2);

            end



            gpu.set(x_aligned, y_aligned + index, line:sub(1, self.width));




            index = index + 1;

        end

    end



    label.destroy = function(self)

        -- TODO: implement

    end




    return label;

end

--- Returns a button which calls given callback function when pressed.
--- When pressed the button's color changes to color_selected and returns back to normal after 1 second
function graphics.button(x, y, width, height, label, color_background, color_selected, color_label, callback)
    
    local button = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        label = label,

        color_background = color_background,
        color_selected = color_selected,
        color_label = color_label,

        callback = callback,
        status = false,

        type = "Button"
    }, Element);



    button.paint = function(self)

        --- Draw button rectangle, in button color according to current status
        gpu.setBackground((self.status and self.color_selected or self.color_background));
        gpu.fill(self.x, self.y, self.width, self.height, " ");

        --- Draw button label, centered on button, in font color
        gpu.setForeground(self.color_label);
        gpu.set(graphics.justify(self.x, self.y, self.width, self.height, self.label));

    end



    button.call = function(self, _event, x_pressed, y_pressed, button_pressed, user)

        if _event == "touch" then

            self.status = true;
            self:redraw();

            self:callback(x_pressed, y_pressed, button_pressed, user);

        end

    end




    return button;

end

--- Returns a switch which stays in either one position (on/off) until switched again.
--- Depending on current status, either color_unselected or color_selected is used. color_switch is the color of the knob and remains unchanged upon status change.
function graphics.switch(x, y, width, height, color_background, color_unselected, color_selected, color_switch, callback)

    local switch = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        color_background = color_background,
        color_unselected = color_unselected,
        color_selected = color_selected,
        color_switch = color_switch,

        callback = callback,
        status = false,

        type = "Switch"
    }, Element);



    switch.paint = function(self)

        --- Draw rectangle in which switch knob moves
        gpu.setBackground((self.status and self.color_selected or self.color_unselected));
        gpu.fill(self.x + 1, self.y + 1, self.width - 2, self.height - 2, " ");

        --- Draw actual switching knob, in second color or selected color
        gpu.setBackground(self.color_switch);
        gpu.fill(self.x + (self.status and (self.width - (self.height - 2) - 2) or 2), self.y + 1, self.height - 2, self.height - 2, " ");

    end



    switch.call = function(self, _event, x_pressed, y_pressed, button)

        if _event == "touch" then

            self.status = not self.status;

            self:callback(x_pressed, y_pressed, button);
            self:redraw();

        end

    end



    switch.destroy = function(self)

        -- TODO: implement
        
    end




    return switch;

end

--- Returns a list (optionally with border and label) containing multiple elements (list:entry_add) with selection of one element at a time.
--- The callback is called only when another entry than the current one is selected.
function graphics.list(x, y, width, height, border, border_label, color_background, color_selected, color_label, color_border, color_border_background, color_border_label, callback)
    
    local list = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        border = border,
        border_label = border_label,
        
        color_background = color_background,
        color_selected = color_selected,
        color_label = color_label,
        color_border = color_border,
        color_border_background = color_border_background,
        color_border_label = color_border_label,

        callback = callback,
        entries = {},
        index = 0,

        type = "List"
    }, Element);



    list.entry_add = function(self, label, value, color)

        self.entries[ #self.entries + 1 ] = {
            label = label,
            value = value,
            color = color or self.color_label
        };

    end

    list.entry_remove = function(self, index)

        table.remove(self, index);

    end



    list.paint = function(self)

        local position = 1;

        -- TODO: not just strip elements overflowing height, but add scrolling behaviour
        while position <= self.height do

            local entry = self.entries[ position ] or {label = "", value = 0, color = self.color_label};

            --- Draw label of entry
            gpu.setBackground(((position == self.index) and self.color_selected or self.color_background)); --- current to-be-drawn entry maybe selected one, so draw in color_selected this time
            gpu.setForeground( entry.color );

            gpu.set(self.x, self.y + position - 1, entry.label:sub(1, self.width)..string.rep(" ", self.width - entry.label:len())); -- self.width-entry.label:len() is desired to be filled with spaces


            position = position + 1;

        end

    end



    list.call = function(self, _event, x_pressed, y_pressed, button)

        if _event == "touch" then

            local index_pressed = utils.math.round(y_pressed - self.y + 1);

            --- If pressed index isn't the current one AND it is in range of the elements, set index to new, call callback and redraw 
            if index_pressed ~= self.index and index_pressed <= #self.entries then

                self.index = index_pressed;

                self:callback();
                self:redraw();
            
            end

        end

    end




    return list;

end

--- Returns a log displaying programs most recent happenings in a terminal-like view.
--- Log an event with log:log_add, then redraw using log:redraw().
function graphics.log(x, y, width, height, label, color_background, color_border, color_label)

    local log = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        label = label,

        color_background = color_background,
        color_border = color_border,
        color_label = color_label,

        entries = {},

        type = "Log"
    }, Element);



    log.log_add = function(self, log_text, color, skip_redraw)

        table.insert(self.entries, 1, {
            text = tostring( log_text ) or "N/A",
            color = color or self.color_label
        });

        if not skip_redraw then
            self:redraw();
        end

    end

    log.log_remove = function(self, entry)

        -- TODO: remove entry by index or table id or even at all??

    end



    log.paint = function(self)

        gpu.setBackground( self.color_border );
        gpu.fill(self.x, self.y, self.width, 1, " "); --- draw top bar, 1-wide
        gpu.fill(self.x, self.y + 1, 2, self.height - 1, " "); --- draw left side bar, 2-wide, 1 beneath top bar
        gpu.fill(self.x + self.width - 1, self.y + 1, 1, self.height - 1, " "); --- draw right side bar, 2-wide, 1 beneath top bar


        gpu.setForeground(self.color_label);
        gpu.fill(self.x + 1, self.y + self.height - 1, 1, 1, ">"); --- draw i/o marker at bottom of box


        --- Draw list entries in font color
        local position = 1;

        -- TODO: not just strip elements overflowing height, but add scrolling behaviour
        while position < self.height do

            local entry = self.entries[position] or {text = "", color = 0};

            --- Draw label of entry
            gpu.setBackground( self.color_background );
            gpu.setForeground( entry.color );

            gpu.set(self.x + 3, self.y + self.height - position, entry.text:sub(1, self.width - 3)); --- draw logs in box, one next to the output markers from above


            position = position + 1;

        end

    end



    log.destroy = function(self)

        -- TODO: implement

    end



    if label then

        local element_label = graphics.label(
            2,
            1,
            width - 2,
            1,
            label,

            color_border,
            color_label,

            "LEFT"
        );

        log:child_add( element_label );

    end




    return log;

end


function graphics.histogram_vertical(x, y, width, height, value_max, value_unit, values_count, color_background, color_data, color_labels, show_labels)

    local histogram_vertical = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        values = {},
        values_count = values_count or 0,
        value_current = 0,
        value_max = value_max,
        value_unit = value_unit,

        color_background = color_background or colors.grey_light,
        color_data = color_data or colors.grey_dark,
        color_labels = color_labels or colors.white,
        show_labels = show_labels,

        type = "Vertical Histogram"
    }, Element);



    histogram_vertical.paint = function(self)

        --- Corrected values for when labels are displayed
        local x_graph = self.x;
        local width_graph = self.width;
        local values_count_graph = self.values_count;

        --- Labels for max, half and min values (full, half full, empty)
        local text_max;
        local text_half;
        local text_min;

        --- X- and y-positions of value labels
        local x_text;
        local y_text_max;
        local y_text_half;
        local y_text_min;

        --- Most recent value and it's y-position in graph
        local value_current;
        local value_current_y = 0;


        if show_labels then

            --- Format value labels to unit strings
            text_max = utils.math.adjust_value(self.value_max, self.value_unit);
            text_half = utils.math.adjust_value(self.value_max / 2, self.value_unit);
            text_min = utils.math.adjust_value(0, self.value_unit);

            --- Positions of labels
            x_text = x_graph;
            y_text_max = self.y;
            y_text_half = y_text_max + (self.height / 2);
            y_text_min = y_text_max + (self.height - 1);

            --- Shift graph to right and strip width
            local shift = text_max:len() + 2;
            x_graph = x_graph + shift;
            width_graph = width_graph - (shift - 1);

            local ratio_shift = (shift - 1) / width_graph; --- Ratio of shift to original width for adjusting values_count
            values_count_graph = math.ceil( values_count_graph * (1 - ratio_shift) );


            -- Set label back- and foreground
            gpu.setBackground( self.color_background );
            gpu.setForeground( self.color_labels );

            --- Draw labels (0, half and max)
            local text_len = math.max(text_max:len(), text_half:len(), text_min:len());
            gpu.set( graphics.justify_x(x_text, y_text_max, text_len + 2, text_max) );
            gpu.set( graphics.justify_x(x_text, y_text_half, text_len + 2, text_half) );
            gpu.set( graphics.justify_x(x_text, y_text_min, text_len + 2, text_min) );

            --- Draw vertical line to seperate labels and graph
            gpu.fill(x_text + (text_len + 1), y_text_max, 1, y_text_min - 2, "▐");

        end


        --- Determine factors to calculate values into graph scaling
        local scaling_x = width_graph / values_count_graph; --- X-axis-length / amount of values = n pixels per index
        local scaling_y = self.height / self.value_max; --- Y-axis-length / maximum value = n pixels per value
        local bar_width = scaling_x; --- Width of single value-bar

        value_current = self.values[ 1 ] or 0;

        --- Copies previous bars to the left, avoids redrawing whole values table (see commented for-loop below) since old values usually don't change
        gpu.copy(
            x_graph + 1, self.y, width_graph, self.height,
            -1, 0
        );

        --- Iterate over given values; determine x- and y-pos for current bar/value in graph (left-right and top-bottom);
        --for index = 1, values_count_graph do

            --local value = self.values[ 1 ] or 0;
            local value = value_current;
            local index = 1;

            local bar_x = scaling_x * (values_count_graph - index) + x_graph --- Convert raw index of value (+ x-offset ('x_graph' when labels shown)) into scaling of graph -> left-right
            local bar_height = scaling_y * value --- Convert raw value into scaling of graph -> top-bottom
            local bar_y = (self.y + self.height - math.ceil( bar_height )); --- Bottom of graph - bar height = bar's y-position


            --- If labels are enabled, save most recent value (index #1) to 'value_current' and draw label
            if show_labels and index == 1 then
                value_current = value;

                value_current_y = scaling_y * value_current; --- Calculate label's y-pos for most recent value (so label sits at y-pos of most recent value's graph bar)
            end

            --- Fill areas between bar top and bottom of graph with color_data (draws actual bars from top to bottom, not only y-coordinates)
            gpu.setBackground( self.color_data );
            gpu.fill(bar_x, bar_y, bar_width, math.ceil( bar_height ), " ");

            gpu.setForeground( self.color_labels );
            gpu.set(x_graph, (self.height - value_current_y) + ((value_current_y == 0) and 2 or self.y), utils.math.adjust_value(value_current, self.value_unit)); --- Draw most recent value's label with offset of 2 or 'y'
            
        --end
        
    end




    return histogram_vertical;

end

function graphics.progress_bar(x, y, width, height, value_max, value_unit, color_function, border, border_label, color_border, color_border_background, color_border_label)

    local progress_bar = setmetatable({
        x = utils.math.round(x),
        y = utils.math.round(y),
        width = utils.math.round(width),
        height = utils.math.round(height),

        value_current = 0,
        value_max = value_max,
        value_unit = value_unit,

        color_background = (color_function or graphics.color_function_default)(),
        color_function = color_function or graphics.color_function_default,

        border = border,
        border_label = border_label,
        color_border = color_border,
        color_border_background = color_border_background,
        color_border_label = color_border_label,

        type = "Progress Bar"
    }, Element);



    progress_bar.paint = function(self)

        local value_percent = self.value_current / self.value_max; --- How much percent the current value is of max possible value
        local value_width = value_percent * self.width; --- Relative width of progressed area

        local value_text_percent = string.format("%.2f", value_percent * 100).." %"; --- Text to dislay (XX %)
        local value_text_total = utils.math.adjust_value(self.value_current, self.value_unit); --- Text to dislay (XX RF)


        --- Fill progressed area with according color -> color_function with percentage as parameter
        gpu.setBackground( self.color_function( value_percent ) );
        gpu.fill(self.x, self.y, value_width, self.height, " ");

        gpu.set( graphics.justify(self.x, self.y, self.width, self.height - 1, value_text_percent) );
        gpu.set( graphics.justify(self.x, self.y, self.width, self.height + 1, value_text_total) );

    end




    return progress_bar;

end

--- Maps percentage to indicating color
function graphics.color_function_default(percent)

    if percent == nil then

        return colors.grey_light;

    elseif percent <= 0.05 then

        return colors.red_dark;

    elseif percent <= 0.1 then

        return colors.red;

    elseif percent <= 0.25 then

        return colors.orange;

    elseif percent <= 0.5 then

        return colors.yellow;

    else

        return colors.green;

    end

end



-- Return table
return graphics;