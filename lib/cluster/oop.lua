local Meta = {};

function Meta:new()
    local o = {};
    setmetatable(o, self);
    self.__index = self;
    return o;
end

function Meta:alter(tat)
    self.tis = tat;
end

return Meta;