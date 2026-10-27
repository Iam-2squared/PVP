extends RefCounted
## Read-only frontend reference data from README sections 4, 7 and 8.
## sample_profile() is display-only demo data, not initial game balance or a save.


static func jobs() -> Array[Dictionary]:
	return [
		{
			"id": "warrior", "name": "戦士",
			"tagline": "近接攻撃と打たれ強さが基本",
			"weapon": "剣", "bonus": "筋力への配分効果 ＋10％",
			"skill_id": "strong_strike", "skill": "強撃", "skill_description": "力を込めた高威力の一撃",
			"second_jobs": [
				{"name": "騎士", "bonus": "筋力・耐久力への配分効果 各＋10％", "skills": "踏み込み斬り：短く接近して斬る\n迎撃の構え：正面攻撃を軽減して剣で反撃"},
				{"name": "重戦士", "bonus": "筋力・HPへの配分効果 各＋10％", "skills": "薙ぎ払い：正面を広く斬る\n叩き割り：強打して一時的に敵の防御を下げる"},
			],
		},
		{
			"id": "mage", "name": "メイジ",
			"tagline": "魔法による攻撃と妨害の基礎を扱う",
			"weapon": "魔法杖", "bonus": "MPへの配分効果 ＋10％",
			"skill_id": "flame_burst", "skill": "火炎爆発", "skill_description": "狭い範囲を炎で攻撃",
			"second_jobs": [
				{"name": "元素術師", "bonus": "MP・敏捷力への配分効果 各＋10％", "skills": "火炎爆発：小範囲の炎攻撃\n氷結弾：攻撃と移動速度低下"},
				{"name": "秘術師", "bonus": "MP・精神力への配分効果 各＋10％", "skills": "結界：一時的に被ダメージを軽減\n幻影：攻撃しない偽の姿で惑わす"},
			],
		},
		{
			"id": "scout", "name": "斥候",
			"tagline": "素早い移動と敵の発見が得意",
			"weapon": "短剣", "bonus": "敏捷力への配分効果 ＋10％",
			"skill_id": "vital_thrust", "skill": "急所突き", "skill_description": "会心が出やすい一撃",
			"second_jobs": [
				{"name": "盗賊", "bonus": "敏捷力・器用さへの配分効果 各＋10％", "skills": "背刺し：背後から大ダメージ\n毒刃：毒による継続ダメージ"},
				{"name": "遊撃兵", "bonus": "敏捷力・HPへの配分効果 各＋10％", "skills": "飛び込み斬り：接近しながら攻撃\n退き斬り：攻撃しながら後退"},
			],
		},
		{
			"id": "archer", "name": "弓使い",
			"tagline": "距離を保ち、矢で攻撃する",
			"weapon": "弓", "bonus": "器用さへの配分効果 ＋10％",
			"skill_id": "piercing_arrow", "skill": "貫通矢", "skill_description": "敵を貫いて直線上を攻撃",
			"second_jobs": [
				{"name": "射手", "bonus": "器用さ・筋力への配分効果 各＋10％", "skills": "貫通矢：直線を貫く矢\n狙い撃ち：狙いを定めて高威力の一射"},
				{"name": "狩人", "bonus": "器用さ・敏捷力への配分効果 各＋10％", "skills": "連射：矢を続けて射る\n足止め矢：敵の移動を遅くする"},
			],
		},
		{
			"id": "cleric", "name": "僧侶",
			"tagline": "回復と聖なる術で仲間を支える",
			"weapon": "聖杖", "bonus": "精神力への配分効果 ＋10％",
			"skill_id": "heal", "skill": "ヒール", "skill_description": "自分か味方のHPを回復",
			"second_jobs": [
				{"name": "司祭", "bonus": "精神力・MPへの配分効果 各＋10％", "skills": "ヒール：単体回復\n癒しの輪：周囲の味方をまとめて回復"},
				{"name": "武僧", "bonus": "精神力・筋力への配分効果 各＋10％", "skills": "三連打：素早い連続打撃\n気功：自分のHPを回復"},
			],
		},
		{
			"id": "artisan", "name": "工匠",
			"tagline": "戦闘道具を使って攻撃や援護を行う",
			"weapon": "工具槌", "bonus": "器用さへの配分効果 ＋10％",
			"skill_id": "thrown_bomb", "skill": "投擲爆弾", "skill_description": "小さな爆弾で範囲攻撃",
			"second_jobs": [
				{"name": "工兵", "bonus": "器用さ・耐久力への配分効果 各＋10％", "skills": "投擲爆弾：小範囲の爆発攻撃\n簡易防壁：攻撃を遮る小型障壁"},
				{"name": "錬金術師", "bonus": "器用さ・回復力への配分効果 各＋10％", "skills": "腐蝕瓶：継続ダメージ\n治癒霧：範囲内の味方を徐々に回復"},
			],
		},
	]


static func sample_profile() -> Dictionary:
	# Numeric values only demonstrate the UI. Initial stats, money and equipment
	# have not been decided; these values must not become gameplay defaults.
	return {
		"username": "冒険者",
		"level": 1,
		"job_id": "warrior",
		"exp": 0,
		"gold": 0,
		"fame": "なし",
		"stats": {
			"筋力": 0, "耐久力": 0, "精神力": 0, "HP": 0,
			"MP": 0, "回復力": 0, "敏捷力": 0, "器用さ": 0,
		},
		"skills": {"strong_strike": 1},
		"equipment": {"head": "", "body": "", "legs": "", "feet": ""},
		"owned_weapons": [],
	}
