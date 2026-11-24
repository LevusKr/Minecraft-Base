local utils_file = require("cluster/utils-file")
local component = require("component")

print("Testing utils_file.read with non-existent file...")
local success, result = utils_file.read("/non/existent/file.txt")
if not success then
    print("Success: Error message received: " .. tostring(result))
else
    print("Failure: Expected error, got success")
end

print("\nTesting utils_file.write with invalid path...")
local success, result = utils_file.write("/non/existent/dir/file.txt", "test data")
if not success then
    print("Success: Error message received: " .. tostring(result))
else
    print("Failure: Expected error, got success")
end
