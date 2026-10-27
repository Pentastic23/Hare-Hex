# events.gd  (autoload "Events")
extends Node

enum Phase { PREP, COMBAT, RESULT }

signal phase_changed(phase: int)
signal gold_changed(amount: int)
signal shop_rolled(offers: Array)
signal unit_bought(data: UnitData)
signal combat_ended(player_won: bool)
signal xp_changed(level: int, xp: int, needed: int)
signal reroll_pressed
signal buy_xp_pressed
signal board_limit_hit
signal unit_sold(data: UnitData, star: int, refund: int)
signal unit_ascended(unit: Unit)   # a 3-star unit reached 4 stars (the Ancient Sigil)
signal round_changed(stage: int, round_in_stage: int)
signal streak_changed(wins: int, losses: int)
signal hp_changed(hp: int)
signal run_won
signal run_lost
signal items_changed                  # GameState.me.items changed (drop, equip, sell, merge)
signal item_drag_started(index: int)  # index into GameState.me.items
signal item_drag_ended
signal shop_lock_changed(locked: bool)
signal team_plan_changed              # SaveGame team plan edited in the team planner
signal opponent_announced(text: String)   # who the coming fight is against (async PvP); "" = nothing to show
signal notice(text: String, color: Color)   # a short message flashed over the board (fight results, BOARD FULL)
signal trophies_changed(trophies: int, losses: int)   # async PvP: fights won (10 wins the run) and lives lost (10 ends it)
signal king_changed                  # the local player's king run power changed (KingPowers; the King tab)
signal fight_speed_changed(speed: int)   # fast forward (async PvP, campaign chapters): 1, 2 or 3
