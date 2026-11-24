class_name NelvarMutationCatalog
extends RefCounted
## Every mutation the Wanderer can get. Each one gains something and costs
## something; which side matters more depends on the version (see
## NelvarMutation.VERSION_WEIGHTS), so the same card is a gift for one
## version and a curse for another.
##
## Values are for stage I; stage II doubles them.


static func all() -> Array[NelvarMutation]:
	var M := NelvarMutation
	var STATS := NelvarMutation.Layer.STATS
	var ABILITY := NelvarMutation.Layer.ABILITY
	var RULE := NelvarMutation.Layer.RULE
	var list: Array[NelvarMutation] = [
		# --- Body: plain trades of characteristics -------------------------
		M.create(&"light_body", "Лёгкое тело", STATS, [
			_pct(&"move_speed", 20), _pct(&"acceleration", 20), _pct(&"max_health", -20)]).described("Ты быстрее, но хрупче."),
		M.create(&"stone_skin", "Каменная кожа", STATS, [
			_pct(&"damage_taken", -20), _pct(&"move_speed", -12)]).described("Удары по тебе слабее, но ты медлительнее."),
		M.create(&"fury", "Ярость", STATS, [
			_pct(&"damage", 25), _pct(&"damage_taken", 25)]).described("Бьёшь сильнее, но и сам получаешь больше."),
		M.create(&"swelling", "Разбухание", STATS, [
			_pct(&"max_health", 40), _pct(&"acceleration", -40)]).described("Здоровья больше, но ты тяжело разгоняешься."),
		M.create(&"short_breath", "Частое дыхание", STATS, [
			_pct(&"primary_cooldown", -25), _pct(&"primary_spread", 150)]).described("Стреляешь чаще, но менее метко."),
		M.create(&"hunger", "Голод", STATS, [
			_flat(&"kill_heal", 3), _pct(&"max_health", -20)]).described("Убийства лечат, но здоровья меньше."),
		M.create(&"overgrowth", "Нарост", STATS, [
			_flat(&"regen", 1), _pct(&"damage", -15)]).described("Раны затягиваются сами, но урон ниже."),
		M.create(&"thick_blood", "Густая кровь", STATS, [
			_pct(&"invulnerability", 50), _pct(&"move_speed", -10)]).described("Дольше неуязвим после удара, но медлительнее."),
		M.create(&"restlessness", "Беспокойство", STATS, [
			_pct(&"adaptation_gain", 35), _pct(&"max_health", -12)]).described("Мутируешь быстрее, но здоровья меньше."),

		# --- Abilities: change how a skill works ---------------------------
		M.create(&"split_shot", "Расщепление", ABILITY, [
			_flat(&"primary_projectiles", 2), _pct(&"primary_damage", -40)]).described("Стреляешь веером, но каждый снаряд слабее."),
		M.create(&"piercing_wind", "Пронизывающий ветер", ABILITY, [
			_flat(&"projectile_pierce", 1), _pct(&"projectile_speed", -25)]).described("Снаряды пробивают врагов, но летят медленнее."),
		M.create(&"far_wave", "Дальняя волна", ABILITY, [
			_pct(&"wave_range", 60), _pct(&"wave_damage", -25)]).described("Волна бьёт дальше, но слабее."),
		M.create(&"broad_wave", "Широкая волна", ABILITY, [
			_pct(&"wave_size", 33), _pct(&"wave_cooldown", 35)]).described("Волна шире, но перезаряжается дольше."),
		M.create(&"long_flight", "Долгий полёт", ABILITY, [
			_pct(&"flight_duration", 50), _pct(&"flight_cooldown", 40)]).described("Летаешь дольше, но реже."),
		M.create(&"gust", "Порыв", ABILITY, [
			_pct(&"flight_speed", 30), _pct(&"flight_duration", -30)]).described("Полёт быстрее, но короче."),
		M.create(&"iron_grip", "Хватка", ABILITY, [
			_pct(&"compression_damage", 60), _pct(&"compression_cooldown", 40)]).described("Сжатие сильнее, но перезаряжается дольше."),
		M.create(&"long_reach", "Дальняя хватка", ABILITY, [
			_pct(&"compression_range", 60), _pct(&"compression_damage", -25)]).described("Сжатие дотягивается дальше, но слабее."),

		# --- Rules: change what the player is used to ----------------------
		M.create(&"hollow_vortex", "Полый вихрь", RULE, [
			_pct(&"flight_cooldown", -50), _pct(&"flight_duration", 30),
			_flag(&"flight_unprotected")],
			[], ["В полёте тебя можно ранить"], 1).described("Летаешь часто и долго, но в полёте уязвим."),
		M.create(&"rooting", "Укоренение", RULE, [
			_flat(&"still_armor", 60), _flat(&"moving_vulnerability", 20)],
			["Стоя на месте: получаемый урон -60%"],
			["В движении: получаемый урон +20%"], 1).described("Крепок, пока стоишь; уязвим в движении."),
		M.create(&"storm_core", "Штормовое ядро", RULE, [
			_flat(&"air_damage", 60), _flat(&"ground_damage", -20)],
			["В полёте: урон +60%"], ["На земле: урон -20%"], 1).described("Сильнее в полёте, слабее на земле."),
		M.create(&"last_breath", "Последний вздох", RULE, [
			_flat(&"low_health_damage", 60), _flat(&"low_health_speed", 25),
			_pct(&"max_health", -15)],
			["Ниже 30% здоровья: урон +60%, скорость +25%"], [], 1).described("На грани смерти сильнее и быстрее, но здоровья меньше."),
	]
	return list


static func _pct(stat: StringName, percent: float) -> Dictionary:
	return {"stat": stat, "percent": percent}


static func _flat(stat: StringName, amount: float) -> Dictionary:
	return {"stat": stat, "flat": amount}


static func _flag(stat: StringName) -> Dictionary:
	return {"stat": stat, "flat": 1.0, "fixed": true}
