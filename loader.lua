--[[
    ⚡ Phantom Engine v4.2 — Loader
    
    HOW TO USE:
    1. Upload "script.lua" to one of these:
       • GitHub   → create repo, upload script.lua, get the RAW url
       • Pastebin → paste the code, get raw url (https://pastebin.com/raw/XXXXXX)
       
    2. Replace the URL below with your raw URL
    
    3. Give this loader to people. They paste this one-liner in their executor:
       loadstring(game:HttpGet("YOUR_RAW_LOADER_URL"))()
]]

-- ═══════════════════════════════════════
-- CHANGE THIS TO YOUR RAW SCRIPT URL
-- ═══════════════════════════════════════
local SCRIPT_URL = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/script.lua"

-- anti-double-load
if getgenv and getgenv().PhantomLoaded then
    warn("[Phantom Engine] Already loaded, skipping.")
    return
end
if getgenv then getgenv().PhantomLoaded = true end

-- load with error handling
local success, err = pcall(function()
    loadstring(game:HttpGet(SCRIPT_URL, true))()
end)

if not success then
    warn("[Phantom Engine] Failed to load: " .. tostring(err))
    -- fallback: try without cache
    pcall(function()
        loadstring(game:HttpGet(SCRIPT_URL))()
    end)
end
