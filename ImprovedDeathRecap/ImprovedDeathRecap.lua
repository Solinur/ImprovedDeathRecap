-- define local variables as much as possible, so scope is local
-- see http://lua-users.org/wiki/ScopeTutorial
local em = GetEventManager()
local wm = GetWindowManager()
local _,tlw
local dx = 1/GetSetting(SETTING_TYPE_UI, UI_SETTING_CUSTOM_SCALE)

IDR = IDR or {}
local IDR = IDR
 
IDR.name 		= "ImprovedDeathRecap"
IDR.version 	= "0.4.23"
IDR.settings 	= {}

IDR.defaults = 
{
	MaxEvents=30,
	MaxDeaths=10,
	WinWidth=700,
	WinHeight=300,
	WinPos={TOPLEFT,GuiRoot,TOPLEFT,100,200},
	WinLock=false,
	WinOpacity=90,
	ShowOnDeath=true,
	HideOnRevive=true,
	HideWinDelay=2,
	HideOnCombat=true,
	ShowAfterCombat=false,
	Winfontsize=18,
	stamthreshold=5000,
	deathhistory={}
}

function IDR.Hide(delay, button)
	local delay = delay or false
	local button = button or 1
	if (delay ==true and IDR.delayinprogress==false) or button~=1 then return end
	tlw:SetHidden(true)
	IDR.delayinprogress=false
end

function IDR.Toggle()
	tlw:SetHidden(not tlw:IsControlHidden())
	IDR.delayinprogress=false
end

function IDR.Show()
	tlw:SetHidden(false)
	IDR.delayinprogress=false
end

function IDR.MoveWin()

    -- Get the new position and dimensions
    local isValidAnchor, point, relativeTo, relativePoint, offsetX, offsetY = tlw:GetAnchor()
    local width , height = tlw:GetDimensions()

	-- Save the new settings
    if ( isValidAnchor ) then IDR.settings.WinPos = {point,relativeTo,relativePoint,offsetX,offsetY} end
	IDR.settings.WinWidth = width
	IDR.settings.WinHeight = height
	IDR.AdjustSlider()	
end

function IDR.OnSliderValueChanged(slider, value, eventReason) -- self should be slider
	local buffer = slider:GetParent():GetNamedChild("Buffer")
	local numHistoryLines = buffer:GetNumHistoryLines()
	local sliderValue = math.max(slider:GetValue(), math.floor((buffer:GetNumVisibleLines()+1)/dx)) -- correct for ui scale
	if eventReason == EVENT_REASON_HARDWARE then
		buffer:SetScrollPosition(numHistoryLines-sliderValue)
	end
end

function IDR.OnScrollButton(self, delta) -- self should be one of the slider buttons
	local slider = self:GetParent()
	local buffer = slider:GetParent():GetNamedChild("Buffer")
	if delta~=nil and delta~=0 then 
		buffer:SetScrollPosition(math.min(buffer:GetScrollPosition()+delta, math.floor(buffer:GetNumHistoryLines()))) -- correct for ui scale
		slider:SetValue(slider:GetValue()-delta)
	else	
		buffer:SetScrollPosition(0)
		slider:SetValue(buffer:GetNumHistoryLines())
	end
end

function IDR.OnScrollMouse(buffer, delta, ctrl, alt, shift)  -- self should be buffer
	local slider = buffer:GetParent():GetNamedChild("Slider")
	if shift then
		delta = delta * math.floor((buffer:GetNumVisibleLines())/dx) -- correct for ui scale
	elseif ctrl then
		delta = delta * buffer:GetNumHistoryLines()
	end
	buffer:SetScrollPosition(math.min(buffer:GetScrollPosition() + delta, math.floor(buffer:GetNumHistoryLines()))) -- correct for ui scale
	slider:SetValue(slider:GetValue() - delta)
end

function IDR.AdjustSlider()	
	local slider = tlw:GetNamedChild("Slider")
	local buffer = tlw:GetNamedChild("Buffer")
	local numHistoryLines = buffer:GetNumHistoryLines()
	local numVisHistoryLines = math.floor((buffer:GetNumVisibleLines()+1)/dx) --it seems numVisHistoryLines is getting screwed by UI Scale
	local bufferScrollPos = buffer:GetScrollPosition()
	local sliderMin, sliderMax = slider:GetMinMax()
	local sliderValue = slider:GetValue()
	
	slider:SetMinMax(0, numHistoryLines)
	
	-- If the sliders at the bottom, stay at the bottom to show new text
	if sliderValue == sliderMax then
		slider:SetValue(numHistoryLines)
	-- If the buffer is full start moving the slider up
	elseif numHistoryLines == buffer:GetMaxHistoryLines() then
		slider:SetValue(sliderValue-1)
	end -- Else the slider does not move
	
	-- If there are more history lines than visible lines show the slider
	if numHistoryLines > numVisHistoryLines then 
		slider:SetHidden(false)
		slider:SetThumbTextureHeight(math.max(20, math.floor(numVisHistoryLines/numHistoryLines*slider:GetHeight())))
	else
		-- else hide the slider
		slider:SetHidden(true)
	end
end

function IDR.UpdateDeathList() --similar to ZO_ComboBox_Base:AddItems(items) but with ipairs

	local items = IDR.settings.deathhistory
	
	if items == nil or #items==0 then return end
	local menu = IDR.dropdown
	
	menu:ClearItems()
	
	for k, v in ipairs(items) do -- use ipairs instead of pairs -> no need for sorting
		v.callback = IDR.OnMenuSelect
        menu:AddItem(v, ZO_COMBOBOX_SUPRESS_UPDATE)
    end
	
	menu:UpdateItems()
end

function IDR.OnMenuSelect(combobox, deathtimestamp, data, selectionChanged)
	if selectionChanged then 
		IDR.PostRecap(data) 
	end
end

function IDR.showclipboard()
    IDR.clipboardbox:SetText(IDR.currenttext)
    IDR.clipboard:SetHidden(false)
    IDR.clipboardbox:TakeFocus()
end


function IDR.CombatEvent(eventCode , result , isError , abilityName , abilityGraphic , abilityActionSlotType , sourceName , sourceType , targetName , targetType , hitValue , powerType , damageType , log , sourceUnitId , targetUnitId , abilityId, overFlow)
	local target = ZO_CachedStrFormat("<<!aC:1>>",targetName)
	
	hitValue = overFlow + hitValue
	
	if (hitValue>0 and target==IDR.playername and (result==ACTION_RESULT_DAMAGE or result==ACTION_RESULT_CRITICAL_DAMAGE or result==ACTION_RESULT_DOT_TICK or result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_BLOCKED or result==ACTION_RESULT_BLOCKED_DAMAGE or result==ACTION_RESULT_ABSORBED or result==ACTION_RESULT_DAMAGE_SHIELDED or result==ACTION_RESULT_HEAL or result==ACTION_RESULT_CRITICAL_HEAL or result==ACTION_RESULT_HOT_TICK or result==ACTION_RESULT_HOT_TICK_CRITICAL or result==ACTION_RESULT_FALL_DAMAGE)) then
		local target = ZO_CachedStrFormat("<<!aC:1>>",targetName)
		local source = ZO_CachedStrFormat("<<!aC:1>>",sourceName)
		--d("IDR: "..target.." is hit by ".. source.." with "..GetAbilityName(abilityId).." for ".. hitValue.." -- ("..targetType..","..IDR.groupstatus..")")
		local timenow = GetSecondsSinceMidnight()
		local timems = GetGameTimeMilliseconds()
		local currenthp, maxhp, _ = GetUnitPower("player", POWERTYPE_HEALTH)
		local currentstam, maxstam, _ = GetUnitPower("player", POWERTYPE_STAMINA)
		local eventno = #IDR.currenthistory
		if (IDR.newfight==true or IDR.currenthistory[1] == nil) then 
			IDR.currenthistory={} 
			IDR.newfight=false			
			IDR.currenthistory[1] = {target=target, source=source, ability=abilityId, dmgtype=damageType, value=hitValue, hits=1, ttype=targetType, result=result, htime=timenow, timems=timems, currenthp=currenthp, maxhp=maxhp, currentstam=currentstam, maxstam=maxstam}
			eventno = 1
		elseif (IDR.currenthistory[eventno]["target"] == target and
				IDR.currenthistory[eventno]["source"] == source and
				IDR.currenthistory[eventno]["ability"] == abilityId and
				IDR.currenthistory[eventno]["dmgtype"] == damageType and
				(timems - IDR.currenthistory[eventno]["timems"])<100) then  -- pool events which are similar and happen within 100ms
			IDR.currenthistory[eventno]["value"] = IDR.currenthistory[eventno]["value"]+hitValue
			IDR.currenthistory[eventno]["hits"] = IDR.currenthistory[eventno]["hits"]+1
		else
			table.insert(IDR.currenthistory,eventno+1,{target=target, source=source, ability=abilityId, dmgtype=damageType, value=hitValue, hits=1, ttype=targetType, result=result, htime=timenow, timems=timems, currenthp=currenthp, maxhp=maxhp, currentstam=currentstam, maxstam=maxstam})
			if eventno-1 > IDR.settings.MaxEvents then table.remove(IDR.currenthistory,1) end
		end 
	end	
end

function IDR.OnDeath(isDead)
    if isDead then 
		local deathtimems = GetGameTimeMilliseconds()
		local deathtimestamp = GetDateStringFromTimestamp(GetTimeStamp())..", "..GetTimeString()
		table.insert(IDR.settings.deathhistory,1,{data=IDR.currenthistory, name=deathtimestamp, deathtimems=deathtimems})
		if #IDR.settings.deathhistory > IDR.settings.MaxDeaths then table.remove(IDR.settings.deathhistory,#IDR.settings.deathhistory) end 
		IDR.UpdateDeathList()
		IDR.dropdown:SelectItemByIndex(1, true)
		zo_callLater(function () IDR.PostRecap(IDR.settings.deathhistory[1]) end, 50)
		if IDR.settings.ShowOnDeath == true then IDR.Show() end
	else
		if IDR.settings.HideOnRevive == true then 
			IDR.delayinprogress = true
			zo_callLater(function () IDR.Hide(true) end, IDR.settings.HideWinDelay*1000)
		end
	end
end

function IDR.OnPlayerCombatState(event, inCombat)
	local wasopen = tlw:IsControlHidden()
	if (inCombat==true) then 
		IDR.newfight=true
		if IDR.settings.HideOnCombat == true then IDR.Hide() end
	elseif (inCombat==false) then
		if (IDR.settings.ShowAfterCombat == true and wasopen==true) then IDR.Show() end
	end 
end

function IDR.Write( message , color )

	-- Validate args
	if ( message == nil ) then return end
	local color = color or {0.6,0.6,0.6}

	-- Write to the log
	tlw:GetNamedChild("Buffer"):AddMessage( message , unpack(color) )
	IDR.AdjustSlider()
end

function IDR.PostRecap(deathdata)
	local crit, crit2, hit, hit2, addinfo = "", "", "", "", ""
	local color = {0.9,0.9,0.7}
	local data = deathdata.data or {}
	local deathtime = deathdata.deathtimems
	local datatext = ""
	tlw:GetNamedChild("Buffer"):Clear()
	for i,j in pairs(data) do
		local cleanabilityName = zo_strformat("<<!aC:1>>",GetAbilityName(j.ability))
		--crits
		if (j.result==ACTION_RESULT_CRITICAL_DAMAGE or j.result==ACTION_RESULT_DOT_TICK_CRITICAL) then
			crit = " |cEEEEEEcritically|r"
			crit2 = " critically"
		elseif(	j.result==ACTION_RESULT_CRITICAL_HEAL or j.result==ACTION_RESULT_HOT_TICK_CRITICAL) then 
			crit = " |cEEEEEEcritically|r"
			crit2 = " critically"
		else
			crit = ""
			crit2 = ""
		end
		--Type of event
		if (j.result==ACTION_RESULT_DAMAGE or j.result==ACTION_RESULT_CRITICAL_DAMAGE or j.result==ACTION_RESULT_DOT_TICK or j.result==ACTION_RESULT_DOT_TICK_CRITICAL) then 			
			hit = " hits with "
			color = {0.9,0.5,0.5}
		elseif (j.result==ACTION_RESULT_BLOCKED or j.result==ACTION_RESULT_BLOCKED_DAMAGE) then 			
			hit = " hits the |cEEEEEEblock|r with "
			hit2 = " hits the block with "
			color = {1,0.7,0.4}
		elseif (j.result==ACTION_RESULT_ABSORBED or j.result==ACTION_RESULT_DAMAGE_SHIELDED) then 			
			hit = " gets absorbed by "
			color = {0.7,0.7,0.7}		
		elseif (j.result==ACTION_RESULT_HEAL or j.result==ACTION_RESULT_CRITICAL_HEAL or j.result==ACTION_RESULT_HOT_TICK or j.result==ACTION_RESULT_HOT_TICK_CRITICAL) then 
			hit = " heals with "
			color = {0.5,0.9,0.5}
		elseif (j.result==ACTION_RESULT_FALL_DAMAGE) then
			color = {0.5,0.5,0.8}
			hit = "You got hurt by  " 
			cleanabilityName = " falling down"
		else 
			hit = "unknown event: "..j.result
			color = {0.9,0.9,0.7}
		end
		
		--get precise time
		local deltatime = "|cEEEEEE["..string.format("%.3f",(j.timems-deathtime)/1000).."s]|r "
		local deltatime2 = "["..string.format("%.3f",(j.timems-deathtime)/1000).."s] "
		--alter color for HP
		local n = math.floor(j.currenthp/j.maxhp*31)+1
		local s,t = "F","0"
		if n<=16 then
			t = string.sub("0123456789ABCDEF", n, n)
		else
			n = n-16
			s = string.sub("FEDCBA9876543210", n, n)
			t = "F"
		end
		local hpcolor = s..s..t..t.."00"	
		local hp = "|c"..hpcolor.."HP:"..j.currenthp.."/"..j.maxhp.."|r "
		local hp2 = "HP:"..j.currenthp.."/"..j.maxhp.." "
		local stam = ""
		local stam2 = ""
		if j.currentstam<IDR.settings.stamthreshold or IDR.settings.stamthreshold==0 then
			stam = " |c00BB00[Stam:"..j.currentstam.."/"..j.maxstam.."] |r "
			stam2 = " [Stam:"..j.currentstam.."/"..j.maxstam.."]"
		end
		--compose number of hits bit
		if j.hits>1 then addinfo = "("..tostring(j.hits).."x)" else addinfo = "" end
		--compose message
		--d(hit)
		--d(deltatime,j.source,crit,hit,j.ability," for ","|cEEEEEE[",j.value,"]|r ",addinfo,"HP:",j.currenthp,"/",j.maxhp)
		
		local icon = zo_iconFormat(GetAbilityIcon(j.ability), IDR.settings.Winfontsize, IDR.settings.Winfontsize).." "
		local dmgcol = IDR.dmgcolors[j.dmgtype]
		local message = (deltatime..hp..j.source..crit..hit..dmgcol..icon..cleanabilityName.."|r for ".."|cEEEEEE"..j.value.."|r "..addinfo..stam)
		local text = (deltatime2..hp2..j.source..crit2..(hit2 or hit)..cleanabilityName.." for "..j.value.." "..addinfo..stam2.."\n")
		if datatext ~= "" then datatext = datatext.." | "..text else datatext = text end
		IDR.Write(message , color)
	end
	IDR.currenttext = datatext
end

-- Slash Commands

function IDR.Slash(extra)
	local extra = extra or "help"
	if extra == "show" then
		IDR.forceopen = true
		IDR.Show()		
	elseif extra == "hide" then
		IDR.forceopen = false
		IDR.Hide()
	else
	d(GetString(SI_IMPROVED_DEATH_RECAP_HELPTEXT))
	end
end

SLASH_COMMANDS["/idr"] = IDR.Slash

-- LAM Stuff
function IDR.MakeMenu()
    -- load the settings->addons menu library
	local menu = LibAddonMenu2
	local set = IDR.settings

    -- the panel for the addons menu
	local panel = {
		type = "panel",
		name = "Improved Death Recap",
		displayName = "Improved Death Recap",
		author = "Solinur",
        version = "" .. IDR.version,
		registerForRefresh = true,
		registerForDefaults = true,
	}

    --this addons entries in the addon menu
	local options = {
		{
			type = "header",
			name = SI_IMPROVED_DEATH_RECAP_MENU_HEADER
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_SAVEDEVENTS,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_SAVEDEVENTS_TT,
			min = 5,
			max = 100,
			step = 1,
			getFunc = function() return set.MaxEvents end,
			setFunc = function(value)
				set.MaxEvents = value
			end,
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_SAVEDDEATHS,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_SAVEDDEATHS_TT,
			min = 1,
			max = 30,
			step = 1,
			getFunc = function() return set.MaxDeaths end,
			setFunc = function(value)
				set.MaxDeaths = value
			end,
		},
		{
			type = "checkbox",
			name = SI_IMPROVED_DEATH_RECAP_MENU_LOCKWINDOW,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_LOCKWINDOW_TT,
			getFunc = function() return tlw:IsMouseEnabled() end,
			setFunc = function(value) 
				set.WinLock = value
				tlw:SetMouseEnabled(not value)
			end,
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_OPACITY,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_OPACITY_TT,
			min = 0,
			max = 100,
			step = 5,
			getFunc = function() return set.WinOpacity end,
			setFunc = function(value)
				set.WinOpacity = value
				tlw:GetNamedChild("Bg"):SetAlpha(value/100)
			end,
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_FONTSIZE,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_FONTSIZE_TT,
			min = 8,
			max = 24,
			step = 1,
			getFunc = function() return set.Winfontsize end,
			setFunc = function(value)
				set.Winfontsize = value
				tlw:GetNamedChild("Buffer"):SetFont(GetString(SI_IMPROVED_DEATH_RECAP_FONT).."|"..value)
			end,
		},
		{
			type = "checkbox",
			name = SI_IMPROVED_DEATH_RECAP_MENU_HIDEONREVIVE,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_HIDEONREVIVE_TT,
			getFunc = function() return set.HideOnRevive end,
			setFunc = function(value)
				set.HideOnRevive = value
			end,
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_HIDEONREVIVE_DELAY,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_HIDEONREVIVE_DELAY_TT,
			min = 0,
			max = 30,
			step = 1,
			getFunc = function() return set.HideWinDelay end,
			setFunc = function(value)
				set.HideWinDelay = value
			end,
			disabled = function() return (not set.HideOnRevive) end,
		},
		{
			type = "checkbox",
			name = SI_IMPROVED_DEATH_RECAP_MENU_HIDEINCOMBAT,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_HIDEINCOMBAT_TT,
			getFunc = function() return set.HideOnCombat end,
			setFunc = function(value)
				set.HideOnCombat = value
			end,
		},
		{
			type = "checkbox",
			name = SI_IMPROVED_DEATH_RECAP_MENU_SHOWAFTERCOMBAT,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_SHOWAFTERCOMBAT_TT,
			getFunc = function() return set.ShowAfterCombat end,
			setFunc = function(value)
				set.ShowAfterCombat = value
			end,
		},
		{
			type = "slider",
			name = SI_IMPROVED_DEATH_RECAP_MENU_STAMINATHRESHOLD,
			tooltip = SI_IMPROVED_DEATH_RECAP_MENU_STAMINATHRESHOLD_TT,
			min = 0,
			max = 80000,
			step = 1000,
			getFunc = function() return set.stamthreshold end,
			setFunc = function(value)
				set.stamthreshold = value
			end,
		},
	}
	
	menu:RegisterAddonPanel("IDROptions", panel)
	menu:RegisterOptionControls("IDROptions", options)
end

-- Initialization
function IDR:Initialize(event, addon)
	if addon ~= IDR.name then return end
	
	em:UnregisterForEvent(IDR.name.."load", EVENT_ADD_ON_LOADED)
  
	-- load saved variables
  
	IDR.settings = ZO_SavedVars:NewCharacterIdSettings(IDR.name.."SavedVariables", 3, nil, IDR.defaults)
	--IDR.settings = IDR.defaults
	
	tlw = IDR_TLW2
	
	IDR.currenthistory = {}
	IDR.Groupnames = {}

	IDR.playername = zo_strformat("<<!aC:1>>",GetUnitName("player"))
  
	-- Register Events and filter them for specific types. Should be more efficient then getting them all and throwing most of them away
	-- The filter will limit the events to the group members / the player only.
  
	em:RegisterForEvent(IDR.name.."combat", EVENT_COMBAT_EVENT , IDR.CombatEvent)
	em:AddFilterForEvent(IDR.name.."combat", EVENT_COMBAT_EVENT, REGISTER_FILTER_UNIT_TAG_PREFIX, "player", REGISTER_FILTER_IS_ERROR, false)
			
	em:RegisterForEvent(IDR.name.."death",  EVENT_PLAYER_DEAD, function(...) IDR.OnDeath(true) end)
	em:RegisterForEvent(IDR.name.."death2",  EVENT_PLAYER_ALIVE, function(...) IDR.OnDeath(false) end)
     
	em:RegisterForEvent(IDR.name.."incombat",  EVENT_PLAYER_COMBAT_STATE , IDR.OnPlayerCombatState)
	
	ZO_CreateStringId("SI_BINDING_NAME_TOGGLE_DEATH_RECAP", "Toggle Improved Death Recap")
	
	IDR.delayinprogress=false
	
	IDR.MakeMenu()

	IDR.forceopen = false
	
	tlw:ClearAnchors()
	tlw:SetAnchor(unpack(IDR.settings.WinPos))
	tlw:SetDimensions(IDR.settings.WinWidth,IDR.settings.WinHeight)
	tlw:GetNamedChild("Title"):SetFont(GetString(SI_IMPROVED_DEATH_TITLE_FONT))
	tlw:GetNamedChild("Buffer"):SetFont(GetString(SI_IMPROVED_DEATH_RECAP_FONT).."|"..IDR.settings.Winfontsize)
	tlw:GetNamedChild("Bg"):SetAlpha(IDR.settings.WinOpacity/100)
	tlw:SetMouseEnabled(not IDR.settings.WinLock)
	
	IDR.dropdown = ZO_ComboBox_ObjectFromContainer(tlw:GetNamedChild("ComboBox"))
	IDR.dropdown:SetSortsItems(false)
	IDR.UpdateDeathList()
	
	IDR.clipboard = tlw:GetNamedChild("Clipboard")
	IDR.clipboardbox = IDR.clipboard:GetNamedChild("Container"):GetNamedChild("Box")
	
    IDR.clipboardbox:SetMaxInputChars(100000)
    IDR.clipboardbox:SetFont(GetString(SI_IMPROVED_DEATH_RECAP_FONT).."|"..IDR.settings.Winfontsize)
    IDR.clipboardbox:SetHandler("OnTextChanged", function(control)
        control:SelectAll()
    end)
    IDR.clipboardbox:SetHandler("OnFocusLost", function()
        IDR.clipboard:SetHidden(true)
    end)
	
	IDR.dmgcolors={ 
		[DAMAGE_TYPE_NONE] 		= "|cE6E6E6", 
		[DAMAGE_TYPE_GENERIC] 	= "|cE6E6E6", 
		[DAMAGE_TYPE_PHYSICAL] 	= "|cf4f2e8", 
		[DAMAGE_TYPE_FIRE] 		= "|cff6600", 
		[DAMAGE_TYPE_SHOCK] 	= "|cffff66", 
		[DAMAGE_TYPE_OBLIVION] 	= "|cd580ff", 
		[DAMAGE_TYPE_COLD] 		= "|cb3daff", 
		[DAMAGE_TYPE_EARTH] 	= "|cbfa57d", 
		[DAMAGE_TYPE_MAGIC] 	= "|c9999ff", 
		[DAMAGE_TYPE_DROWN] 	= "|ccccccc", 
		[DAMAGE_TYPE_DISEASE] 	= "|cc48a9f", 
		[DAMAGE_TYPE_POISON] 	= "|c9fb121", 
	}
	
end

-- Finally, we'll register our event handler function to be called when the proper event occurs.
em:RegisterForEvent(IDR.name.."load", EVENT_ADD_ON_LOADED, function(...) IDR:Initialize(...) end)