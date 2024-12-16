---@class ConfigVariable
---@field name string
---@field description string
---@field defaultValue string
---@field shouldSave boolean|nil

---@type ConfigVariable[]
local convars = {
    { name = "chat_bubbles_enable",                description = "Enable or disable the overhead chat bubbles",                           defaultValue = "1" },

    { name = "chat_bubbles_expiration_seconds",    description = "How long the chat message will be displayed above the player's head",   defaultValue = "5" },
    { name = "chat_bubbles_fade_seconds",          description = "How long it takes for the chat message to fade out, after they expire", defaultValue = "2" },
    { name = "chat_bubbles_max_messages",          description = "How many messages to display above a player's head",                    defaultValue = "5" },

    { name = "chat_bubbles_max_line_length",       description = "Max line length for chat bubbles",                                      defaultValue = "70" },
    { name = "chat_bubbles_long_message_behavior", description = "How should long messages be handled, split/truncate",                   defaultValue = "split" },

    { name = "chat_bubbles_max_distance",          description = "Max distance before chat bubbles fade",                                 defaultValue = "500" },
}


for _, convar in ipairs( convars ) do
    convar.shouldSave = true
end

--- allow servers to modify convar defaults before registering
hook.Run( "ChatBubbles_PreRegisterConvars", convars )

for _, convar in ipairs( convars ) do
    CreateConVar( convar.name, convar.defaultValue, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, convar.description )
end

local expiresConvar = GetConVar( "chat_bubbles_expiration_seconds" )
local fadeTimeConvar = GetConVar( "chat_bubbles_fade_seconds" )
local maxMessagesConvar = GetConVar( "chat_bubbles_max_messages" )
local enableConvar = GetConVar( "chat_bubbles_enable" )
local maxTextSize = GetConVar( "chat_bubbles_max_line_length" )
local maxDistanceConvar = GetConVar( "chat_bubbles_max_distance" )
local longMessageBehaviorConvar = GetConVar( "chat_bubbles_long_message_behavior" )

local disableBloomConvar = GetConVar( "mat_disable_bloom" )

local msgTable = {}
ChatBubbles = {
    enabled = false,
    convars = convars,
}

local entityMeta = FindMetaTable( "Entity" )
local plyMeta = FindMetaTable( "Player" )

local entLookupBone = entityMeta.LookupBone
local entGetBoneMatrix = entityMeta.GetBoneMatrix

local plyIsAlive = plyMeta.Alive
local plyIsTerror = plyMeta.IsTerror
local plyGetObserverMode = plyMeta.GetObserverMode
local OBS_MODE_NONE = OBS_MODE_NONE

---@param ply Player
---@param messages table
local function drawMessages( ply, messages )
    local expiration = expiresConvar:GetFloat()
    local fadeTime = fadeTimeConvar:GetFloat()
    local maxDistance = maxDistanceConvar:GetInt()

    local font = "ChatBubblesFont"

    local boneIndex = entLookupBone( ply, "ValveBiped.Bip01_Head1" )
    if not boneIndex then return end

    local boneMatrix = entGetBoneMatrix( ply, boneIndex )
    if not boneMatrix then return end
    local bonePos = boneMatrix:GetTranslation()

    local pos = bonePos + Vector( 0, 0, 80 )
    local eyePos = LocalPlayer():EyePos()
    local v = pos - eyePos
    local ang = v:GetNormalized():Angle()
    local distance = v:Length()
    ang.y = ang.y - 90
    ang.r = 90
    ang.p = 0

    cam.Start3D2D( pos, ang, 0.1 )
    local yPos = 0
    local yOffset = 625
    local alpha = 255
    if distance > maxDistance then
        alpha = 255 - (distance - maxDistance) / 100 * 255
    end

    for i, message in ipairs( messages ) do
        local v = message.msg
        local timeSince = CurTime() - message.time

        if timeSince > expiration then
            alpha = 255 - ((timeSince - expiration) / fadeTime) * 255
        end

        local white
        -- use a grey if bloom is enabled so text is still readable
        if render.GetHDREnabled() and disableBloomConvar:GetInt() == 0 then
            white = Color( 140, 140, 140, alpha )
        else
            white = Color( 255, 255, 255, alpha )
        end

        local black = Color( 0, 0, 0, alpha )

        surface.SetFont( font )
        local width, height = surface.GetTextSize( v )
        if width < 50 then
            width = 50
        end

        if i == 1 and alpha > 0 then
            surface.SetDrawColor( white )
            local triangle = {
                { x = 0,   y = yOffset - yPos + 30 + height },
                { x = -15, y = yOffset - yPos + 10 + height },
                { x = 15,  y = yOffset - yPos + 10 + height },
            }
            draw.NoTexture()
            surface.DrawPoly( triangle )
        end

        if alpha > 0 then
            draw.RoundedBox( 10, -width / 2 - 10, yOffset - yPos - 10, width + 20, height + 20, white )
            draw.DrawText( v, font, 0, yOffset - yPos, black, TEXT_ALIGN_CENTER )


            yPos = yPos + height + 25
            if message.hasGap == false then
                yPos = yPos - 7
            end
        end
    end

    cam.End3D2D()
end

surface.CreateFont( "ChatBubblesFont", {
    font = "Arial",
    size = 45,
    blursize = 0,
    weight = 900,
    antialias = true,
} )

---@param ply Player
local function shouldDrawPlayermessage( ply )
    if not plyIsAlive( ply ) then
        return false
    end
    if ply:IsDormant() then
        return false
    end
    ---@diagnostic disable-next-line: undefined-field
    if plyIsTerror then
        if not plyIsTerror( ply ) then
            return false
        end
        if ply:GetNWBool( "disguised", false ) then
            return false
        end
    end
    if ply == LocalPlayer() then
        return false
    end
    if plyGetObserverMode( ply ) ~= OBS_MODE_NONE then
        return false
    end
    return true
end

function ChatBubbles.OnPlayerChat( ply, text, isTeam, isDead )
    if not ChatBubbles.enabled then return end

    if isTeam then return end
    if isDead then return end

    if not shouldDrawPlayermessage( ply ) then return end

    local plyMsgTable = msgTable[ply] or {}
    msgTable[ply] = plyMsgTable

    local maxLen = maxTextSize:GetInt()

    local hasGap = true
    local behavior = longMessageBehaviorConvar:GetString()
    if #text > maxLen and behavior == "split" then
        local behavior = longMessageBehaviorConvar:GetString()

        -- insert the first part of the message
        local maxMessages = maxMessagesConvar:GetInt() - 1
        for _ = 1, maxMessages do
            if #text <= maxLen then break end
            local splitAt = maxLen
            local nextSpace = string.find( text, " ", maxLen )
            if nextSpace and nextSpace - maxLen < 10 then
                splitAt = nextSpace
            else
                local prevSpace = string.find( text, " ", maxLen - 10 )
                if prevSpace and prevSpace < maxLen then
                    splitAt = prevSpace
                end
            end


            local split = string.sub( text, 1, splitAt )
            table.insert( plyMsgTable, 1, {
                msg = split,
                ply = ply,
                time = CurTime(),
                hasGap = hasGap
            } )
            hasGap = false
            text = string.sub( text, splitAt + 1 )
        end
    end

    if #text > maxLen then
        text = string.sub( text, 1, maxLen ) .. "..."
    end
    if #text > 0 then
        table.insert( plyMsgTable, 1, {
            msg = text,
            ply = ply,
            time = CurTime(),
            hasGap = hasGap
        } )
    end
end

local function cleanupMsgList()
    local actualExpire = expiresConvar:GetFloat() + fadeTimeConvar:GetFloat()
    local maxMessages = maxMessagesConvar:GetInt()
    for _, messages in pairs( msgTable ) do
        for i = #messages, 1, -1 do
            local timeSince = CurTime() - messages[i].time
            if timeSince > actualExpire then
                table.remove( messages, i )
            end
            if i > maxMessages then
                table.remove( messages, i )
            end
        end
    end

    for ply, messages in pairs( msgTable ) do
        if #messages == 0 then
            msgTable[ply] = nil
        end
        if not IsValid( ply ) then
            msgTable[ply] = nil
        end
    end
end

local function drawPlyChatMessages( ply )
    local messages = msgTable[ply]
    if not messages then return end
    if #messages == 0 then return end
    if not shouldDrawPlayermessage( ply ) then return end

    drawMessages( ply, messages )
end

local function drawAllPlayerChatMessages()
    for _, ply in ipairs( player.GetAll() ) do
        drawPlyChatMessages( ply )
    end
end

local enabled = enableConvar:GetBool()
if enabled then
    hook.Add( "OnPlayerChat", "ChatBubbles_NewMessage", ChatBubbles.OnPlayerChat )
    timer.Create( "ChatBubblesCleanup", 1, 0, cleanupMsgList )
    hook.Add( "PostDrawTranslucentRenderables", "ChatBubbles_Draw", drawAllPlayerChatMessages )
    ChatBubbles.enabled = true
end

cvars.AddChangeCallback( "chat_bubbles_enable", function( convar, _, newValue )
    if convar ~= "chat_bubbles_enable" then return end

    if newValue == "1" then
        hook.Add( "OnPlayerChat", "ChatBubbles_NewMessage", ChatBubbles.OnPlayerChat )
        timer.Create( "ChatBubblesCleanup", 1, 0, cleanupMsgList )
        hook.Add( "PostDrawTranslucentRenderables", "ChatBubbles_Draw", drawAllPlayerChatMessages )
        ChatBubbles.enabled = true
    else
        hook.Remove( "OnPlayerChat", "ChatBubbles_NewMessage" )
        timer.Remove( "ChatBubblesCleanup" )
        hook.Remove( "PostDrawTranslucentRenderables", "ChatBubbles_Draw" )
        ChatBubbles.enabled = false
    end
end )
ChatBubbles.plyIsTerror = plyIsTerror
hook.Add( "InitPostEntity", "UpdateLocals", function()
    plyIsTerror = plyMeta.IsTerror
    ChatBubbles.plyIsTerror = plyIsTerror
end )
