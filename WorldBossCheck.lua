-- Create the main addon frame
local frame = CreateFrame("Frame", "WorldBossCheckFrame", UIParent, "BackdropTemplate")
frame:SetSize(260, 220)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

-- Set backdrop
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})

-- Title
local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
titleText:SetPoint("TOP", 0, -10)
titleText:SetText("World Boss Check")

-- Close button
local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
closeButton:SetSize(24, 24)

-- Boss kill lines
local shaOfAngerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
shaOfAngerText:SetPoint("TOPLEFT", 20, -40)

local galleonText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
galleonText:SetPoint("TOPLEFT", shaOfAngerText, "BOTTOMLEFT", 0, -20)

-- Alts header
local altsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
altsHeader:SetPoint("TOPLEFT", galleonText, "BOTTOMLEFT", 0, -15)
altsHeader:SetText("Characters:")

-- Alt status text
local altStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
altStatusText:SetPoint("TOPLEFT", altsHeader, "BOTTOMLEFT", 0, -5)
altStatusText:SetJustifyH("LEFT")
altStatusText:SetWidth(260)
altStatusText:SetText("Loading...")

-- Reset text
local resetText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
resetText:SetText("Next reset: (loading...)")

-- Refresh button
local refreshButton = CreateFrame("Button", "WorldBossCheckFrameRefreshButton", frame, "UIPanelButtonTemplate")
refreshButton:SetSize(100, 30)
refreshButton:SetText("Refresh")
refreshButton:SetScript("OnClick", function() WorldBossCheck_Update() end)

-- Footer
local footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footerText:SetPoint("BOTTOMRIGHT", -10, 10)
footerText:SetText("Version 0.2")

-- Resize frame based on character count
local function ResizeFrameToFitCharacters(count)
    local baseHeight = 130
    local perAltLine = 15
    local staticUIHeight = 60
    local newHeight = baseHeight + (count * perAltLine) + staticUIHeight
    frame:SetHeight(math.max(newHeight, 180))
end

-- Update alt character list
local function UpdateAltStatusDisplay()
    if not WorldBossCheckDB or not WorldBossCheckDB.characters then return end

    local name, realm = UnitName("player")
    local currentChar = name .. "-" .. (realm or GetRealmName())

    local lines = {}
    for charName, data in pairs(WorldBossCheckDB.characters) do
        if charName ~= currentChar and (data.level or 0) >= 85 then
            local icon
            if data.kills == 2 then
                icon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"
            elseif data.kills == 1 then
                icon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:16|t"
            else
                icon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16|t"
            end

            local status = string.format("%s  %s", icon, data.name)
            table.insert(lines, status)
        end
    end

    table.sort(lines)
    altStatusText:SetText(table.concat(lines, "\n"))
    ResizeFrameToFitCharacters(#lines)

    -- Reposition reset text and refresh button
    local offsetY = -(#lines * 14 + 10)
    resetText:ClearAllPoints()
    resetText:SetPoint("TOPLEFT", altsHeader, "BOTTOMLEFT", 0, offsetY)

    refreshButton:ClearAllPoints()
    refreshButton:SetPoint("TOPLEFT", resetText, "BOTTOMLEFT", 0, -5)
end

-- Update boss kill statuses
function WorldBossCheck_Update()
    local checkIcon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"
    local crossIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16|t"

    -- Ensure database exists
    WorldBossCheckDB = WorldBossCheckDB or {}
    WorldBossCheckDB.characters = WorldBossCheckDB.characters or {}

    -- Reset outdated character data
    local now = time()
    local nextReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
    local thisResetTimestamp = now + nextReset - 604800

    for charName, data in pairs(WorldBossCheckDB.characters) do
        if data.lastUpdate and data.lastUpdate < thisResetTimestamp then
            WorldBossCheckDB.characters[charName].kills = 0
            WorldBossCheckDB.characters[charName].lastUpdate = nil
        end
    end

    -- Current character info
    local name, realm = UnitName("player")
    local level = UnitLevel("player")
    realm = realm or GetRealmName()
    local fullName = name .. "-" .. realm

    -- Automatic cleanup: remove any character entries for this account that match the current character's name but have a different realm
    for charName, data in pairs(WorldBossCheckDB.characters) do
        if data and data.name == name and data.realm ~= realm then
            WorldBossCheckDB.characters[charName] = nil
        end
    end

    -- Ignore and cleanup lowbies
    if level < 85 then
        WorldBossCheckDB.characters[fullName] = nil
        UpdateAltStatusDisplay()
        return
    end

    -- Boss kills
    local shaKilled = C_QuestLog.IsQuestFlaggedCompleted(32099)
    local galleonKilled = C_QuestLog.IsQuestFlaggedCompleted(32098)

    -- Update UI
    shaOfAngerText:SetText("Sha of Anger: " .. (shaKilled and checkIcon or crossIcon))
    galleonText:SetText("Galleon: " .. (galleonKilled and checkIcon or crossIcon))

    -- Save progress
    WorldBossCheckDB.characters[fullName] = {
        name = name,
        realm = realm,
        level = level,
        kills = (shaKilled and 1 or 0) + (galleonKilled and 1 or 0),
        lastUpdate = now,
    }

    UpdateAltStatusDisplay()
end

-- Update reset timer
local function UpdateResetTimer()
    local secondsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
    local days = math.floor(secondsUntilReset / 86400)
    local hours = math.floor((secondsUntilReset % 86400) / 3600)
    local minutes = math.floor((secondsUntilReset % 3600) / 60)
    resetText:SetText(string.format("Next reset: %dd %dh %dm", days, hours, minutes))
end

-- Timer updater
local elapsed = 0
frame:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed >= 1 then
        UpdateResetTimer()
        elapsed = 0
    end
end)

-- Weekly refresh scheduler
local function ScheduleWeeklyRefresh()
    local secondsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
    C_Timer.After(secondsUntilReset + 1, function()
        print("WorldBossCheck: Weekly reset occurred! Refreshing boss data.")
        WorldBossCheck_Update()
        ScheduleWeeklyRefresh()
    end)
end

-- Auto update events
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local level = UnitLevel("player")
        local shaKilled = C_QuestLog.IsQuestFlaggedCompleted(32099)
        local galleonKilled = C_QuestLog.IsQuestFlaggedCompleted(32098)
        if level < 85 or (shaKilled and galleonKilled) then
            frame:Hide()
        else
            frame:Show()
        end
        WorldBossCheck_Update()
        UpdateResetTimer()
        ScheduleWeeklyRefresh()
    elseif event == "QUEST_LOG_UPDATE" then
        WorldBossCheck_Update()
    end
end)

-- Minimap Button via LibDataBroker
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local dbicon = LibStub("LibDBIcon-1.0")

local ldbIcon = ldb:NewDataObject("WorldBossCheck", {
    type = "data source",
    text = "World Boss Check",
    icon = "Interface\\Icons\\inv_axe_2h_pandaraid_d_01",
    OnClick = function(_, button)
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("World Boss Check")
        tooltip:AddLine("Click to toggle window", 1, 1, 1)
    end,
})

WorldBossCheckDB = WorldBossCheckDB or {}
WorldBossCheckDB.minimap = WorldBossCheckDB.minimap or {}
dbicon:Register("WorldBossCheck", ldbIcon, WorldBossCheckDB)
dbicon:Show("WorldBossCheck")
