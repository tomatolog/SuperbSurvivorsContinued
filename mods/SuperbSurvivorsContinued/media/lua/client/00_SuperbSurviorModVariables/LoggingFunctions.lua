ModId = "SuperbSurvivorsContinued";

local pl = require('09_GOAP/00_pl')

--[[
    Credit to "haram gaming#4572" in PZ Discord for providing a text file writing example.
    Credit to "albion#0123" in PZ Discord for explaining the difference between "getFileWriter" and "getModFileWriter"
    CreateLogLine will create a log file under the "<user>/Zomboid/Lua/<ModId>/logs".
--]]
-- Use this function to write a line to a text file, this is useful to identify when and how many times a function is called.
function CreateLogLine(fileName, isEnabled, newLine)
    if (isEnabled) then
        local timestamp = os.time();
        local formattedTimeDay = os.date("%Y-%m-%d", timestamp);
        local formattedTime = os.date("%Y-%m-%d %H:%M:%S", timestamp);
        local file = getFileWriter(
            ModId .. "/logs/" .. ModId .. "_" .. fileName .. "_Logs.txt",
            true, -- true to create file if null
            true  -- true to "append" to existing file, false to replace.
        );
        local content = formattedTime .. " : " .. "CreateLogLine called";

        if newLine then
            content = formattedTime .. " : " .. newLine;
        end

        file:write(content .. "\r\n");
        file:close();
    end
end

--[[
    Log the key-value pairs of a table to a specified file.
-- ]]
function LogTableKVPairs(fileName, isEnabled, table)
    if (isEnabled) then
        for key, value in pairs(table) do
            CreateLogLine(fileName, isEnabled, "key:" .. tostring(key) .. " | value: " .. tostring(value));
        end
    end
end

--[[
    Log any number of arguments using pretty printing.
    Similar to CreateLogLine but accepts any arguments and formats them using pl.pretty.write().
    Default values: fileName = '', isEnabled = true
--]]
function logPretty(...)
    local timestamp = os.time();
    local formattedTime = os.date("%Y-%m-%d %H:%M:%S", timestamp);
    local file = getFileWriter(
        ModId .. "/logs/" .. ModId .. ".log",
        true, -- true to create file if null
        true  -- true to "append" to existing file, false to replace.
    );
    
    -- Format arguments using pl.pretty.write()
    -- Empty string as second parameter makes output single-line
    local n = select("#", ...)
    local formattedContent
    if n == 0 then
        formattedContent = ""
    elseif n == 1 then
        local arg = select(1, ...)
        formattedContent = pl.pretty.write(arg, '')
    else
        -- Multiple arguments: format as a table similar to pretty.debug
        local argsTable = { ... }
        formattedContent = pl.pretty.write(argsTable, '')
    end
    
    local content = formattedTime .. " : " .. formattedContent
    file:write(content .. "\r\n");
    file:close();
end

local LogLevel = {
    info  = 1,
    debug = 2,
    error = 3
}

local g_eLogLevel = LogLevel.info

local function logWithLevel(level, ...)
    if level <= g_eLogLevel then
        logPretty(...)
    end
end

function logInfo(...)
    logWithLevel(LogLevel.info, ...)
end

function logDebug(...)
    logWithLevel(LogLevel.debug, ...)
end

function logError(...)
    logWithLevel(LogLevel.error, ...)
end

-- Example usage:
-- CreateLogLine("SS_Debugger", true, "Start...");
-- CreateLogPretty({name = "John", age = 30});
-- CreateLogPretty("Status:", {x = 100, y = 200}, 42);