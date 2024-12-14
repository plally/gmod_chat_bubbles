local expiresConvar = CreateClientConVar( "chat_bubbles_expiration_seconds", "5", true, false, "How long the chat message will be displayed above the player's head" )
local fadeTimeConvar = CreateClientConVar( "chat_bubbles_fade_seconds", "2", true, false, "How long it takes for the chat message to fade out, after they expire" )
local maxMessagesConvar = CreateClientConVar( "chat_bubbles_max_messages", "2", true, false, "How many messages to display above a player's head" )
local enableConvar = CreateClientConVar( "chat_bubbles_enable", "1", true, false, "Enable or disable the overhead chat bubbles" )
local maxTextSize = CreateClientConVar( "chat_bubbles_max_line_length", "80", true, false, "Max line length for chat bubbles", 1, 150 )

local msgTable = {}
ChatBubbles = {}

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
    local font = "ChatBubblesFont"

    local boneIndex = entLookupBone( ply, "ValveBiped.Bip01_Head1" )
    if not boneIndex then return end

    local boneMatrix = entGetBoneMatrix( ply, boneIndex )
    if not boneMatrix then return end
    local bonePos = boneMatrix:GetTranslation()

    local pos = bonePos + Vector( 0, 0, 80 )
    local ang = EyeAngles()
    ang.y = ang.y - 90
    ang.r = 90
    ang.p = 0

    cam.Start3D2D( pos, ang, 0.1 )
    local yPos = 0
    local yOffset = 640
    local alpha = 255

    for i, message in ipairs( messages ) do
        local v = message.msg
        local timeSince = CurTime() - message.time

        if timeSince > expiration then
            alpha = 255 - ((timeSince - expiration) / fadeTime) * 255
        end

        local white = Color( 255, 255, 255, alpha )
        local black = Color( 0, 0, 0, alpha )

        if i == 1 and alpha > 0 then
            surface.SetDrawColor( white )
            local triangle = {
                { x = 0,   y = yOffset - yPos + 60 },
                { x = -15, y = yOffset - yPos + 40 },
                { x = 15,  y = yOffset - yPos + 40 },
            }
            draw.NoTexture()
            surface.DrawPoly( triangle )
        end


        if alpha > 0 then
            surface.SetFont( font )
            local width, height = surface.GetTextSize( v )

            draw.RoundedBox( 10, -width / 2 - 10, yOffset - yPos - 10, width + 20, height + 20, white )
            draw.DrawText( v, font, 0, yOffset - yPos, black, TEXT_ALIGN_CENTER )

            yPos = yPos + height + 25
        end
    end

    cam.End3D2D()
end

surface.CreateFont( "ChatBubblesFont", {
    font = "Arial",
    size = 30,
    blursize = 0,
    weight = 900,
    antialias = true,
} )

---@param ply Player
local function shouldDrawPlayermessage( ply )
    if not plyIsAlive( ply ) then
        return false
    end
    ---@diagnostic disable-next-line: undefined-field
    if plyIsTerror and not plyIsTerror( ply ) then
        return false
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

    if #text > maxLen then
        text = string.sub( text, 1, maxLen ) .. "..."
    end

    table.insert( plyMsgTable, 1, {
        msg = text,
        ply = ply,
        time = CurTime(),
    } )
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

local enabled = enableConvar:GetBool()
if enabled then
    hook.Add( "OnPlayerChat", "ChatBubbles_NewMessage", ChatBubbles.OnPlayerChat )
    timer.Create( "ChatBubblesCleanup", 1, 0, cleanupMsgList )
    hook.Add( "PostPlayerDraw", "ChatBubbles_Draw", drawPlyChatMessages )
    ChatBubbles.enabled = true
end

cvars.AddChangeCallback( "chat_bubbles_enable", function( convar, _, newValue )
    if convar ~= "chat_bubbles_enable" then return end

    if newValue == "1" then
        hook.Add( "OnPlayerChat", "ChatBubbles_NewMessage", ChatBubbles.OnPlayerChat )
        timer.Create( "ChatBubblesCleanup", 1, 0, cleanupMsgList )
        hook.Add( "PostPlayerDraw", "ChatBubbles_Draw", drawPlyChatMessages )
        ChatBubbles.enabled = true
    else
        hook.Remove( "OnPlayerChat", "ChatBubbles_NewMessage" )
        timer.Remove( "ChatBubblesCleanup" )
        hook.Remove( "PostPlayerDraw", "ChatBubbles_Draw" )
        ChatBubbles.enabled = false
    end
end )
