-- Create the main addon frame
local frame = CreateFrame("Frame", "WorldBossCheckFrame", UIParent, "BackdropTemplate")
-- slightly larger so delete buttons have breathing room
frame:SetSize(320, 260)
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
-- Container for character rows
local altsContainer = CreateFrame("Frame", nil, frame)
altsContainer:SetPoint("TOPLEFT", altsHeader, "BOTTOMLEFT", 0, -5)
altsContainer:SetSize(280, 180)

-- Row pool
local rowPool = {}
local activeRows = {}

local function AcquireRow()
    local row = table.remove(rowPool)
    if row then return row end
    row = CreateFrame("Frame", nil, altsContainer)
    row:SetSize(280, 18)

    row.icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetWidth(24)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWidth(220)

    row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.deleteBtn:SetSize(20, 20)
    row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    return row
end

local function ReleaseRow(row)
    row:Hide()
    row.icon:SetText("")
    row.nameText:SetText("")
    row.deleteBtn:Hide()
    row.deleteBtn:SetScript("OnClick", nil)
    table.insert(rowPool, row)
end

-- Delete helper (defined early so confirm dialog can call it)
local function DeleteCharacter(fullName)
    if not WorldBossCheckDB or not WorldBossCheckDB.characters then return false end
    if WorldBossCheckDB.characters[fullName] then
        WorldBossCheckDB.characters[fullName] = nil
        return true
    end
    return false
end

-- forward declare confirmFrame so row handlers reference the local upvalue (set later)
local confirmFrame
-- forward declare ShowConfirmToDelete so row handlers can call it
local ShowConfirmToDelete

-- Reset text
local resetText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
resetText:SetText("Next reset: (loading...)")

-- Refresh button

-- Footer
local footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footerText:SetPoint("BOTTOMRIGHT", -10, 10)
footerText:SetText("Version 0.3")

-- Checkbox for auto-open preference
local autoOpenCheckbox = CreateFrame("CheckButton", "WorldBossCheckAutoOpenCheckbox", frame, "ChatConfigCheckButtonTemplate")
-- move lower to avoid overlapping the reset timer
autoOpenCheckbox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
autoOpenCheckbox.Text:SetText("Show on login if bosses incomplete")
autoOpenCheckbox:SetChecked(true)
autoOpenCheckbox:SetScript("OnClick", function(self)
    WorldBossCheckDB.autoOpen = self:GetChecked()
end)

-- Initialize checkbox state from DB
local function UpdateAutoOpenCheckbox()
    if WorldBossCheckDB and WorldBossCheckDB.autoOpen ~= nil then
        autoOpenCheckbox:SetChecked(WorldBossCheckDB.autoOpen)
    else
        autoOpenCheckbox:SetChecked(true)
    end
end

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
    -- Clear active rows
    for _, row in ipairs(activeRows) do
        ReleaseRow(row)
    end
    wipe(activeRows)

    if not WorldBossCheckDB or not WorldBossCheckDB.characters then return end

    local name, realm = UnitName("player")
    local currentChar = name .. "-" .. (realm or GetRealmName())

    -- Collect display entries
    local entries = {}
    for charName, data in pairs(WorldBossCheckDB.characters) do
        if charName ~= currentChar and (data.level or 0) >= 85 then
            table.insert(entries, { key = charName, data = data })
        end
    end

    table.sort(entries, function(a,b) return a.data.name < b.data.name end)

    -- Create rows
    for i, entry in ipairs(entries) do
        local row = AcquireRow()
        row:SetPoint("TOPLEFT", altsContainer, "TOPLEFT", 0, -(i-1) * 16)
        local data = entry.data
        local icon
        if data.kills == 2 then
            icon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"
        elseif data.kills == 1 then
            icon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:16|t"
        else
            icon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16|t"
        end
        row.icon:SetText(icon)
        row.nameText:SetText(data.name .. " - " .. data.realm)
        row.deleteBtn:Show()
        row.deleteBtn:SetScript("OnClick", function()
            ShowConfirmToDelete(entry.key)
        end)
        row:Show()
        table.insert(activeRows, row)
    end

    ResizeFrameToFitCharacters(#entries)

    -- Reposition reset text
    local offsetY = -(#entries * 16 + 10)
    resetText:ClearAllPoints()
    resetText:SetPoint("TOPLEFT", altsHeader, "BOTTOMLEFT", 0, offsetY)
end

-- Confirmation dialog factory (lazy-created)
local targetToDelete = nil
local function EnsureConfirmFrame()
    if confirmFrame then return end
    confirmFrame = CreateFrame("Frame", "WorldBossCheckConfirmFrame", UIParent, "BackdropTemplate")
    confirmFrame:SetSize(300, 100)
    confirmFrame:SetPoint("CENTER")
    confirmFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    confirmFrame:Hide()

    confirmFrame.title = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirmFrame.title:SetPoint("TOP", 0, -8)
    confirmFrame.title:SetText("Confirm Deletion")

    confirmFrame.text = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    confirmFrame.text:SetPoint("TOP", confirmFrame.title, "BOTTOM", 0, -8)
    confirmFrame.text:SetWidth(260)
    confirmFrame.text:SetJustifyH("CENTER")

    local yesBtn = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    yesBtn:SetSize(100, 24)
    yesBtn:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOM", -110, 12)
    yesBtn:SetText("Yes")
    yesBtn:SetScript("OnClick", function()
        if targetToDelete then
            if DeleteCharacter(targetToDelete) then
                print("WorldBossCheck: Removed " .. targetToDelete)
                UpdateAltStatusDisplay()
            else
                print("WorldBossCheck: Could not find " .. targetToDelete)
            end
        end
        targetToDelete = nil
        confirmFrame:Hide()
    end)

    local noBtn = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    noBtn:SetSize(100, 24)
    noBtn:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOM", 110, 12)
    noBtn:SetText("No")
    noBtn:SetScript("OnClick", function()
        targetToDelete = nil
        confirmFrame:Hide()
    end)
end

ShowConfirmToDelete = function(fullName)
    EnsureConfirmFrame()
    targetToDelete = fullName
    confirmFrame.text:SetText("Delete saved data for " .. fullName .. "? This action cannot be undone.")
    confirmFrame:Show()
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
        WorldBossCheckDB = WorldBossCheckDB or {}
        UpdateAutoOpenCheckbox()
        local level = UnitLevel("player")
        local shaKilled = C_QuestLog.IsQuestFlaggedCompleted(32099)
        local galleonKilled = C_QuestLog.IsQuestFlaggedCompleted(32098)
        local autoOpen = WorldBossCheckDB.autoOpen
        if level < 85 or (shaKilled and galleonKilled) or (autoOpen == false) then
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
