-- Phantom Engine v4.2 — Loader
-- Execute this in your executor to load the script

local SCRIPT_URL = "https://raw.githubusercontent.com/oscarpooper-lang/BLOX-FRUIT/main/script.lua"

-- anti-double-load handled inside script now, no need here

print("[Phantom Engine] Fetching script...")

local code = nil

-- try fetching
local ok1, err1 = pcall(function()
    code = game:HttpGet(SCRIPT_URL, true)
end)

if not ok1 or not code then
    warn("[Phantom Engine] Failed to fetch: " .. tostring(err1))
    -- retry without cache
    local ok2, err2 = pcall(function()
        code = game:HttpGet(SCRIPT_URL)
    end)
    if not ok2 or not code then
        warn("[Phantom Engine] Retry failed: " .. tostring(err2))
        return
    end
end

print("[Phantom Engine] Script fetched (" .. #code .. " bytes), executing...")

-- execute with visible error
local fn, compileErr = loadstring(code)
if not fn then
    warn("[Phantom Engine] Compile error: " .. tostring(compileErr))
    return
end

local ok3, runErr = pcall(fn)
if not ok3 then
    warn("[Phantom Engine] Runtime error: " .. tostring(runErr))
end
