return {
	multivalue_upgrades = {
		LMOON_STONE_HANYUE_TEST_MEMORY = {
			function (data) -- version 1
				-- 寒月公主的击杀记忆结构发生了变化 string[] -> {prefab: string, count: 0}[]
				return LMOON.map(data, function (mem_str) return {prefab = mem_str, count = 1} end)
			end
		}
	}
}