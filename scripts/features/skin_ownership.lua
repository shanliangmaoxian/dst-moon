-- 小月亮：角色皮肤通用化
-- 允许玩家跨角色套用皮肤，突破原版角色皮肤绑定限制
-- 基于角色列表动态合并 PREFAB_SKINS，并修复更衣室 / 物品收藏界面

local _G = GLOBAL
local CFG = _G.MOON_CFG

if not CFG.ENABLE_SKIN_SHARING then return end

_G.setfenv(1, _G)

-- ============================================================================
-- 可自由套用的基础角色列表（免费角色）
-- ============================================================================
local SHARED_HEROES = {
    "wilson", "willow", "wolfgang", "wendy", "wx78",
    "wickerbottom", "woodie", "wes", "waxwell", "wathgrithr",
    "webber", "winona", "warly", "walter", "wonkey",
}

-- ============================================================================
-- 服务器端：绕过基础皮肤的客户端所有权检查
-- ============================================================================
if TheNet:GetIsServer() then
    -- --- InventoryProxy: 放行所有免费角色的 _none 皮肤 ---
    local _check_client_own = InventoryProxy.CheckClientOwnership
    function InventoryProxy:CheckClientOwnership(...)
        local args = { ... }
        local skin = args[2]
        for _, hero in ipairs(SHARED_HEROES) do
            if skin == hero .. "_none" then return true end
        end
        return _check_client_own(self, ...)
    end

    -- --- ValidateSpawnPrefabRequest: 合并所有在场角色的皮肤列表 ---
    local _validate_spawn = ValidateSpawnPrefabRequest
    function ValidateSpawnPrefabRequest(...)
        local original_skins = deepcopy(PREFAB_SKINS)
        local characters = GetActiveCharacterList()
        for _, hero_a in ipairs(characters) do
            if PREFAB_SKINS[hero_a] then
                for _, hero_b in ipairs(characters) do
                    if original_skins[hero_b] then
                        for _, skin_name in ipairs(original_skins[hero_b]) do
                            table.insert(PREFAB_SKINS[hero_a], skin_name)
                        end
                    end
                end
            end
        end
        local results = { _validate_spawn(...) }
        PREFAB_SKINS = original_skins
        return unpack(results)
    end

    -- --- Wardrobe: 更衣室显示所有角色皮肤 ---
    local Wardrobe = require("components/wardrobe")
    local _activate = Wardrobe.ActivateChanging
    function Wardrobe:ActivateChanging(doer, skins, ...)
        local _get_bases = GetCharacterSkinBases
        GetCharacterSkinBases = function()
            local merged = {}
            for _, hero in ipairs(GetActiveCharacterList()) do
                shallowcopy(_get_bases(hero), merged)
            end
            return merged
        end
        local results = { _activate(self, doer, skins, ...) }
        GetCharacterSkinBases = _get_bases
        return unpack(results)
    end

    -- --- Skinner: 修复皮肤模式回退逻辑 ---
    local Skinner = require("components/skinner")
    function Skinner:SetSkinMode(skin_type, fallback_build)
        skin_type = skin_type or self.skin_type
        self.skin_type = skin_type

        -- 兼容旧存档：无 skin_data 时自动初始化
        if self.skin_data == nil then
            self:SetSkinName(self.inst.prefab .. "_none", nil, true)
        end

        local base_skin
        if skin_type == "ghost_skin" then
            base_skin = self.skin_data[skin_type]
                or self.skin_data["normal_skin"]
                or self.inst.ghostbuild
                or fallback_build
                or "ghost_" .. self.inst.prefab .. "_build"
        else
            base_skin = self.skin_data[skin_type]
                or self.skin_data["normal_skin"]
                or fallback_build
                or self.inst.prefab
        end

        SetSkinsOnAnim(
            self.inst.AnimState,
            self.inst.prefab,
            base_skin,
            self.clothing,
            self.monkey_curse,
            skin_type,
            fallback_build
        )

        self.inst.Network:SetPlayerSkin(
            self.skin_name or "",
            self.clothing["body"] or "",
            self.clothing["hand"] or "",
            self.clothing["legs"] or "",
            self.clothing["feet"] or ""
        )
    end
end

-- ============================================================================
-- 客户端：物品收藏界面 & 皮肤筛选器
-- ============================================================================
if not TheNet:IsDedicated() then
    -- --- InventoryProxy（客户端）：放行 _none 皮肤 ---
    local _check_own = InventoryProxy.CheckOwnership
    function InventoryProxy:CheckOwnership(skin_name, ...)
        for _, hero in ipairs(SHARED_HEROES) do
            if skin_name == hero .. "_none" then return true end
        end
        return _check_own(self, skin_name, ...)
    end

    -- --- ClothingExplorerPanel: 默认展示全部角色筛选 ---
    local ClothingExplorerPanel = require("widgets/redux/clothingexplorerpanel")
    local _ctor = ClothingExplorerPanel._ctor
    function ClothingExplorerPanel:_ctor(...)
        _ctor(self, ...)
        self.filter_bar:ShowFilter("heroFilter")
    end

    -- --- 物品浏览器：合并全角色皮肤 ---
    local _build_explorer = ClothingExplorerPanel._BuildItemExplorer
    function ClothingExplorerPanel:_BuildItemExplorer(...)
        local _get_bases = GetCharacterSkinBases
        GetCharacterSkinBases = function()
            local merged = {}
            for _, hero in ipairs(GetActiveCharacterList()) do
                shallowcopy(_get_bases(hero), merged)
            end
            return merged
        end
        local results = { _build_explorer(self, ...) }
        GetCharacterSkinBases = _get_bases
        return unpack(results)
    end

    -- --- 亲和度筛选：隐藏其他角色的 _none 基础款 ---
    local _affinity_filter = GetAffinityFilterForHero
    function GetAffinityFilterForHero(hero, ...)
        local filter = _affinity_filter(hero, ...)
        return function(item_key, ...)
            if string.sub(item_key, -5) == "_none"
                and string.sub(item_key, 1, -6) ~= hero then
                return false
            end
            return filter(item_key, ...)
        end
    end
end
