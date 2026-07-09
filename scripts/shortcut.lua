--- Shortcut + hotkey handling (DESIGN.md §4.1). The shortcut toggles ALL three
--- global masters together, admins only. For everyone else the shortcut state is a
--- read-only indicator of whether any master is on.

local State = require('__lazy-bastards-friend__.scripts.state')

local Shortcut = {}

--- Keep the toggle indicator in sync for one player. Registered as a State refresh
--- handler so every state change propagates to every player's shortcut bar.
--- @param player LuaPlayer
function Shortcut.sync(player)
    player.set_shortcut_toggled('lbf-toggle', State.any_master())
end

--- @param player LuaPlayer
function Shortcut.toggle(player)
    if not player.admin then
        player.create_local_flying_text({
            text = { 'lbf-message.admins-only' },
            create_at_cursor = true,
        })
        Shortcut.sync(player)
        return
    end

    local turn_on = not State.any_master()
    State.set_all_masters(turn_on)
    game.print({ turn_on and 'lbf-message.enabled' or 'lbf-message.disabled', player.name })
    State.refresh_all()
end

return Shortcut
