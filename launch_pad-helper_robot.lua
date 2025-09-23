local component = require("component");
local os = require("os");
local robot = require("robot");
local sides = require("sides");


local robot_component = component.robot;
local redstone = component.redstone;



function find_mechanical_user_leftie()

    local slot = robot.select(2);

    while robot.count() == 0 and slot < robot.inventorySize() do

        slot = robot.select(slot + 2);

    end

    --- Out of mechanical users. This should never happen since 31 available slots x 64 items in a stack = 1,984 items.
    if robot.count() == 0 then
        return false, "out of lefties";
    end

    return true, slot;

end

function find_mechanical_user_rightie()

    local slot = robot.select(3);

    while robot.count() == 0 and slot < robot.inventorySize() do

        slot = robot.select(slot + 2);

    end

    --- Out of mechanical users. This should never happen since 31 available slots x 64 items in a stack = 1,984 items.
    if robot.count() == 0 then
        return false, "out of righties";
    end

    return true, slot;

end


function move_to_rocket_location()

    robot.up();
    robot.up();
    robot.forward();

end

function move_to_telemetry_location()

    robot.turnRight();
    robot.forward();
    robot.turnLeft();
    robot.forward();
    robot.forward();
    robot.turnRight();

end

function move_to_home(do_abort)

    if not do_abort then

        robot.turnRight();
        robot.forward();
        robot.forward();
        robot.turnRight();
        robot.forward();
        robot.turnLeft();

    else
        robot.turnAround();
    end

    robot.forward();
    robot.down();
    robot.down();
    robot.turnAround();

end

function perform_connect(slot)

    robot.select(slot);

    robot.swingDown();

    local success = robot_component.place(sides.down, sides.back);

    if not success then
        return false;
    end

    robot.select(1); --- Select frequency module slot
    robot.dropDown(); --- Put frequency module in mechanical user

    redstone.setOutput(sides.down, 15);
    os.sleep(1);
    redstone.setOutput(sides.down, 0);

    robot.select(1); --- Select frequency module slot
    robot.suckDown(); --- Retrieve frequency module from mechanical user

    robot.swingDown();
    robot.select(robot.inventorySize()); --- Block will land in last slot due to missing NBT data.
    -- TODO: dispose old mechanical users

    return true;

end


-- function start()

    local success_left, result_left = find_mechanical_user_leftie();
    if success_left then

        move_to_rocket_location();
        local success = perform_connect(result_left);

        if not success then

            print("Couldn't place leftie mechanical user");

            move_to_home(true);

            return false;

        end

    else

        print("No leftie mechanical users found in inventory", success_left, result_left)
        return success_left, result_left;

    end


    local success_right, result_right = find_mechanical_user_rightie();
    if success_right then

        move_to_telemetry_location();
        local success = perform_connect(result_right);

        if not success then

            print("Couldn't place rightie mechanical user");

            move_to_home(false);

            return false;

        end

        move_to_home(false);

    else

        print("No rightie mechanical users found in inventory", success_right, result_right)
        return success_right, result_right;

    end

    -- require("computer").shutdown();

-- end