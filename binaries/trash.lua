local filesystem = require("filesystem");
local term = require("term");

TRASH = "/trash";


local function trashDir()

    if not filesystem.exists(TRASH) then
        filesystem.makeDirectory(TRASH);
    end

end

local function trash(path)

    trashDir();


    local new_path = filesystem.concat(TRASH, path);

    if filesystem.exists(new_path) then
        return false, "Duplicate";
    end


    local copy_success, copy_result = filesystem.copy(path, new_path);

    if not copy_success then
        return false, copy_result;
    end


    local remove_success, remove_result = filesystem.remove(path);

    if not remove_success then
        return false, remove_result;
    end


    return true, new_path;


end


local args = {...};

local to_trash = args[1];

if to_trash then

    print(trash(to_trash));

end