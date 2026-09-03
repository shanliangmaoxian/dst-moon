local Text = require("widgets/text")

local ok, hh_enchant = _G.pcall(function() return require("enums/hh_enchant") end)
if not ok or not hh_enchant then return end
local HH_EQUIP_BUFF_LIST = hh_enchant["HH_EQUIP_BUFF_LIST"]

function HHEffectStoneIngredient(p_effect_id, amount)
    return Ingredient2('hh_effect_stone', amount or 1, {
        test_fn = function(item)
            local effect_id = item.hh_effect or (item.hh_client_effect and item.hh_client_effect:value())
            return effect_id == p_effect_id
        end,
        overlay = function()
            local config = HH_EQUIP_BUFF_LIST[p_effect_id] or {}
            return Text(BODYTEXTFONT, 34, config.client_text or "")
        end
    })
end
