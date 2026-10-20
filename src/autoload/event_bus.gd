extends Node
## 全局事件总线。系统之间只通过信号沟通，避免到处 get_node 互相抓。

signal player_damaged(amount: float, source: Node)
signal player_healed(amount: float)
signal player_downed()
signal player_revived()
signal player_died()
signal player_state_changed(state: String)

signal enemy_killed(enemy: Node, headshot: bool, killer_faction: String)
signal enemy_alerted(enemy: Node)
signal shot_fired(shooter: Node, from: Vector3, to: Vector3, hit: bool)

signal outpost_progress(outpost: Node, value: float)
signal outpost_captured(outpost: Node, owner_faction: String)

signal objective_changed(text: String, detail: String)
signal mission_completed(credits: int, xp: int)
signal mission_failed(reason: String)

signal notify(text: String)
signal hitmarker(kind: String)
