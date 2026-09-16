return {
	multivalue_upgrades = {
		LMOON_STONE_HANYUE_TEST_MEMORY = {
			-- 这里的升级处理程序的具体语义为“从数据对应的版本开始到最终版本所经历的升级程序”，
			-- 并且同时这个列表的长度也表示数据的最新版本号
			-- 例如数据在上次保存时的版本号为 3，这个列表的长度为7，则它需要经历的升级程序为该列表的 [4]、[5]、[6]、[7]
			-- 若对应 Key 的数据结构发生了变化，只需要在这里对应的 Key 的列表末尾增加处理程序即可，不需要在使用时关心版本号
			function (data) -- version 1
				-- 寒月公主的击杀记忆结构发生了变化 string[] -> {prefab: string, count: 0}[]
				return LMOON.map(data, function (mem_str) return {prefab = mem_str, count = 1} end)
			end
		}
	}
}