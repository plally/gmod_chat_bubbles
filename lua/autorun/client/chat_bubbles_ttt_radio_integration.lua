if engine.ActiveGamemode() ~= "terrortown" then return end

hook.Add( "InitPostEntity", "ChatBubblesTTTRadio", function()
    local GetTranslation = LANG.GetTranslation
    local GetPTranslation = LANG.GetParamTranslation

    if GAMEMODE.PlayerSentRadioCommand == nil then return end

    _ChatBubblesOldPlayerSentRadioCommand = _ChatBubblesOldPlayerSentRadioCommand or GAMEMODE.PlayerSentRadioCommand
    ---@diagnostic disable-next-line: inject-field
    GAMEMODE.PlayerSentRadioCommand = function( self, sender, msg, param )
        _ChatBubblesOldPlayerSentRadioCommand( self, sender, msg, param )

        local lang_param = LANG.GetNameParam( param )
        if lang_param then
            if lang_param == "quick_corpse_id" then
                -- special case where nested translation is needed
                param = GetPTranslation( lang_param, { player = net.ReadString() } )
            else
                param = GetTranslation( lang_param )
            end
        end

        local text = GetPTranslation( msg, { player = param } )

        -- don't want to capitalize nicks, but everything else is fair game
        if lang_param then
            text = util.Capitalize( text )
        end
        ChatBubbles.OnPlayerChat( sender, text, false, not sender:Alive() )
    end
end )
