--- Shortcut + hotkey handling (DESIGN.md §4.1). The shortcut is the player's
--- own on/off switch — same per-player master as the switch in the relative
--- panel (data.master), kept in sync both ways through State.set_player_master.
--- Global (everyone) control lives in the admin panel only; in singleplayer,
--- switching on also re-arms the global masters (see State.set_player_master).

local State = require('__lazy-bastards-friend__.scripts.state')

local Shortcut = {}

--- Keep the toggle indicator in sync with the player's master switch.
--- Registered as a State refresh handler.
--- @param player LuaPlayer
function Shortcut.sync(player)
    player.set_shortcut_toggled('lbf-toggle', State.get_player_data(player.index).master)
end

--- @param player LuaPlayer
function Shortcut.toggle(player)
    -- Mirrors the greyed-out master switch: an admin-disabled player can't
    -- flip themselves back on from the toolbar either.
    if State.get_player_data(player.index).locked_master then
        player.create_local_flying_text({
            text = { 'lbf-gui.locked-by-admin' },
            create_at_cursor = true,
        })
        return
    end
    State.set_player_master(player, not State.get_player_data(player.index).master)
    State.refresh(player)
end

return Shortcut
