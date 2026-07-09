--- Additive `script.X` wiring: lets multiple modules subscribe to the same
--- event — including the lifecycle events — without clobbering each other's
--- registration. Every `script.on_event` / `on_init` / `on_load` /
--- `on_configuration_changed` call *replaces* whatever handler was previously
--- registered, so two independent modules calling the same one directly
--- silently drop the first; only the last registrant wins. Every event
--- registration in this mod (control.lua, test-bench levels) goes through
--- `Event` instead of calling `script.X` directly — one real `script.X` call
--- per event, fanning out to every handler added, in registration order —
--- so ordering between modules never matters and nothing gets dropped.
---
--- Modeled after the dispatcher pattern in reference/event.lua and
--- data/core/lualib/event_handler.lua, trimmed to what this mod needs: no
--- tokens, no removal, no nth-tick merging (scheduler.lua/watchdog.lua/
--- harness.lua each own a distinct nth-tick interval, so there's nothing to
--- merge there).

local Event = {}

--- @type table<uint|string, fun(event)[]>
local handlers = {}

--- Register `handler` to run whenever `event_id` fires, without replacing any
--- handler already registered for that event by this or another module.
--- @param event_id defines.events|string
--- @param handler fun(event)
function Event.add(event_id, handler)
    local list = handlers[event_id]
    if not list then
        list = {}
        handlers[event_id] = list
        script.on_event(event_id, function(event)
            for i = 1, #list do
                list[i](event)
            end
        end)
    end
    list[#list + 1] = handler
end

--- Builds an additive registrar for a lifecycle slot (on_init/on_load/
--- on_configuration_changed): one real `script_fn` call, fanning out to every
--- handler added, in registration order.
--- @param script_fn fun(handler: fun(event: table?))
--- @return fun(handler: fun(event: table?))
local function make_lifecycle(script_fn)
    local list = {}
    local registered = false
    return function(handler)
        list[#list + 1] = handler
        if not registered then
            registered = true
            script_fn(function(event)
                for i = 1, #list do
                    list[i](event)
                end
            end)
        end
    end
end

--- Register a handler to run on `script.on_init`, without replacing any
--- handler already registered by another module.
--- @param handler fun()
Event.on_init = make_lifecycle(script.on_init)

--- Register a handler to run on `script.on_load`, without replacing any
--- handler already registered by another module.
--- @param handler fun()
Event.on_load = make_lifecycle(script.on_load)

--- Register a handler to run on `script.on_configuration_changed`, without
--- replacing any handler already registered by another module.
--- @param handler fun(data: ConfigurationChangedData)
Event.on_configuration_changed = make_lifecycle(script.on_configuration_changed)

return Event
