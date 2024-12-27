local function generateSteamConvarTable()
    local convars = ChatBubbles.convars
    local text = "[tr] [th]Name[/th] [th]Description[/th] [th]Default Value[/th] [/tr]\n"
    for _, convar in ipairs( convars ) do
        text = text .. "[tr] [td]" .. convar.name .. "[/td] [td]" .. convar.description .. "[/td] [td]" .. convar.defaultValue .. "[/td] [/tr]\n"
    end
    return "[table]\n" .. text .. "[/table]"
end

concommand.Add( "_chatbubbles_convars_steamtable", function()
    local text = generateSteamConvarTable()
    print( text )
    print( "" )
    SetClipboardText( text )
    print( "Copied to clipboard" )
end )
