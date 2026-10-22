# Opponents, campaign and saves

Roadmap items 4 (opponent provider), 6 (campaign structure) and 7 (save system), plus the sample waves the campaign needs (part of item 5). Built with Opus 5.5 on 2026-10-21; chapter runs (boards carrying between levels) added the same day after review. Not committed until reviewed.

## How it fits together

```
GameManager._ready()
  └─ _begin_run()
       ├─ level = GameState.run_level, else Debug Level (which continues a saved chapter run
       │   in the same chapter if there is one), else none (free play)
       ├─ carry = GameState.begin_run(level, campaign)
       │     carried run: gold, level, XP, HP from the carry (+ the level's start_heal)
       │     fresh start: the level's start_gold / start_level / player_hp
       ├─ roster = level.allowed_units or unit_pool   →   shared_pool (shop)
       ├─ _restore_carry(carry): board, bench, items; owned copies leave the shared pool
       └─ opponents = WaveOpponents(level.waves)  or  RandomOpponents(unit_pool, ...)

start_combat()
  └─ _spawn_enemies()
       └─ spawn_board( opponents.board_for_round(round) )
            ├─ authored coords (nearest open tile if locked/taken), others random
            ├─ star, items, stat_scale per unit
            └─ Synergies.apply(enemies) if board.use_synergies

_end_combat(won)  → won: +1 gold and the wave's hp_reward; lost: HP - damage_for_loss()

RESULT phase, final round
  ├─ campaign: last wave lost → defeat: chapter run ends (save cleared)
  │            won → _win_run(): record completion; next level in the chapter?
  │                   yes → run_carry = make_carry(next), saved as the chapter run
  │                   no  → chapter complete, chapter run cleared
  └─ free play: survive → victory (unchanged)
```

## The board format

Every enemy side is an `EnemyBoard` (`Scripts/enemy_board.gd`), whoever built it:

| Field | Meaning |
|---|---|
| `display_name` | Shown on the top bar in a campaign ("Wave 2/5: Raiders") |
| `units: Array[BoardUnit]` | The enemies |
| `stat_scale` | Multiplies every unit's HP and damage |
| `use_synergies` | Enemies get synergy bonuses from their own tags |
| `hp_reward` | Campaign HP pack: HP restored for beating this board (never above 100) |

`BoardUnit` (`Scripts/board_unit.gd`): `unit: UnitData`, `star` (1-3), `coord` (enemy half: x 0-6, y 0-3, row 3 is the front; `(-1, -1)` = place automatically), `items: Array[ItemData]`.

For saves and future PvP snapshots, `EnemyBoard.to_dict()` / `EnemyBoard.from_dict(dict, unit_roster, item_roster)` convert to plain JSON-safe data. Units are stored by `display_name`, items by `id` (lookups: `EnemyBoard.lookup_unit` / `lookup_item`):

```json
{"name": "Raid Captain", "stat_scale": 0.6, "use_synergies": true, "hp_reward": 10,
 "units": [{"unit": "Guardian", "star": 2, "coord": [3, 3], "items": ["chain_vest"]}]}
```

## Providers

`OpponentProvider` (`Scripts/opponent_provider.gd`) has one method: `board_for_round(round_number) -> EnemyBoard`.

- **RandomOpponents** (free play): the old behaviour moved out of GameManager. Count = player unit cap ±1 (30%), cost limited early, scale `enemy_base_scale + enemy_scale_per_round * (round - 1)`, random placement, no stars, items or synergies. Free-play balance is unchanged.
- **WaveOpponents** (campaign): returns `waves[round - 1]` (rounds past the end repeat the last wave), with the level's `enemy_stat_mult` applied to a copy.
- **Next (PvP, roadmap 9):** a snapshot provider that returns saved player boards. Only a new class is needed; spawning already handles stars, items and coords.

### Spawn rules (`GameManager.spawn_board`)

1. Open enemy tiles are the unlocked, empty ones (enemy tiles unlock with the **player's** level, same as before).
2. Units with a coord go to it, or to the nearest open tile if it's locked or taken.
3. Units without a coord go to random open tiles.
4. If there are more units than open tiles, the extras are skipped with a warning. `CampaignLevel.validate()` catches this while authoring.
5. With `use_synergies`, `Synergies.apply()` runs on the enemies, then they're healed to their new max HP.

## Campaign data

`Campaign` → `CampaignChapter` → `CampaignLevel`, all resources in `tres/campaign/`:

```
tres/campaign/campaign.tres        Campaign (display_name, chapters)
tres/campaign/chapter_1.tres       CampaignChapter (id, display_name, description, levels)
tres/campaign/levels/ch1_l1.tres   CampaignLevel (waves are embedded in the level file)
```

`CampaignLevel` fields:

| Field | Default | Meaning |
|---|---|---|
| `id` | | Stable, unique; the save file uses it. Never rename. |
| `display_name`, `description` | | Shown on the top bar and end screen |
| `waves: Array[EnemyBoard]` | | One per round; the level has as many rounds as waves |
| `start_gold` | 2 | Only when the level **starts** a run (first level of a chapter, or Debug Level) |
| `start_level` | 1 | Same; for later levels it's the level players usually arrive at, and `validate()` uses it |
| `player_hp` | 100 | Same: starting HP of a fresh run |
| `start_heal` | 0 | HP pack when arriving from the previous level |
| `income_bonus` | 0 | Extra gold every round (round 1 included) |
| `enemy_stat_mult` | 1.0 | Difficulty knob on top of each wave's `stat_scale` |
| `loss_damage` | 0 | HP lost per lost wave (+0.25 per surviving enemy star); 0 = free-play formula `5 x stage` (rounds restart every level, so the stage would stay low) |
| `prep_time` | 0 | Seconds; 0 = GameManager's `prep_time` |
| `item_drop_rounds` | [] | Empty = free-play drop rounds |
| `allowed_units` | [] | Empty = full roster in the shop |
| `unlocks: Array[StringName]` | [] | Saved on completion (nothing reads them yet) |

`Campaign` helpers: `all_levels()`, `find_level(id)`, `next_level(level)` (crosses chapters), `next_in_chapter(level)`, `first_of_chapter(level)`, `chapter_of(level)`, `is_unlocked(level)`, `validate()`.

### Chapter runs

A **chapter is one continuous run**, roguelite style:

- **Start:** the chapter's first level starts fresh with its `start_gold`, `start_level` and `player_hp` (100).
- **Carried to the next level:** every unit on the board and bench (star, equipped items, tile or bench slot), the item bar, gold, player level and XP, and HP. Round number and streaks restart; the shop's 1-cost-only first roll doesn't apply.
- **HP packs:** HP carries, and comes back two ways: the next level's `start_heal` on arrival, and `hp_reward` for beating certain waves (in the sample levels, one mid-level wave and every boss). HP never goes above the run's starting HP.
- **Winning a level:** survive every wave **and win the last one** (the boss).
- **Defeat** (HP 0, or losing the boss) ends the chapter run: **Restart chapter** goes back to its first level with an empty board.
- **Chapter complete:** the run ends; the next chapter (when there is one) starts fresh.
- **Unlocks:** linear. The first level is always open; every other level needs the one before it completed.

**End screen:** LEVEL COMPLETE with only **Next level** (your board carries on); CHAPTER COMPLETE with **Next chapter** (if any) and **Play chapter again**; DEFEAT with **Restart chapter**. Free play keeps VICTORY/DEFEAT and Restart.

**Top bar:** "First Blood   Wave 2/5: Raiders" in a campaign (hover it to see the wave's enemies, stars and item counts), "Stage 1-2" in free play. **HP label colours** are relative to the run's starting HP.

### Sample content: chapter 1 "The Borderlands"

| Level | Waves | Settings | Boss | Bot clears (of runs that reach it) |
|---|---|---|---|---|
| First Blood (`ch1_l1`) | 5 | 100 HP, 4 gold, enemies x1.35, loss 6, items rounds 2 and 4; wave 3 +5 HP, boss +10 HP | 2-star Guardian with Chain Vest | about 90% |
| Shadows in the Wood (`ch1_l2`) | 6 | arrive +10 HP, +1 gold/round, x1.8, loss 10, items 2 and 4; wave 3 +5, boss +10 | 2-star Assassin with Longsword + Blood Fang | about 80% |
| The Dragon's Roost (`ch1_l3`) | 7 | arrive +10 HP, x2.2, loss 14, items 2, 4, 6; wave 4 +5, boss +10; unlocks `chapter_1_complete` | 2-star Dragon with Iron Belt + Chain Vest | about 55% |

Regular waves get stronger through each level (`stat_scale` ramps, for example 0.6 to 1.0 in level 2) so a run loses some HP before the boss; bosses are stronger through their stars and items. The bot completes the whole chapter in about 40% of runs (`tools/bot_playtest -- chapter`, 12 runs). The bot is simple, so a human should do better.

Levels 2 and 3 are tuned for **arriving with a carried board**. Started directly from Debug Level they use `start_level` 3 / 5 and `start_gold` 10 / 20, which is still harder than arriving with a board.

### Authoring a level in the editor

1. Duplicate an existing level file in `tres/campaign/levels/` and give it a new `id`.
2. Edit waves in the Inspector: each wave is an EnemyBoard; each unit is a BoardUnit (unit, star, coord, items).
3. Add the level to a chapter's `levels` (order = unlock and play order).
4. Run the game; `validate()` problems are printed as warnings at level start. Check difficulty with `tools/bot_playtest -- chapter`.

Coord tips: row 3 is the enemy front line, row 0 the back; columns 3 and 4 are the center, and those tiles unlock first. At player level 1 only 2 enemy tiles are open, level 2 opens 6, level 3 opens 9, level 5 opens 15 (see `Board.tiles_open_for_level`).

### Starting the campaign

From the **main menu**: **Continue** resumes a saved chapter run at the start of its next level; **Campaign** lists chapters and levels (completed with best HP, not completed, locked) and **Start chapter** begins a fresh run (asking first if that abandons a saved run).

For testing, you can skip the menu: set **Debug Level** on Game Manager in `main.tscn` to a level **file** (e.g. `ch1_l1.tres`) and run main.tscn directly (F6). A "New CampaignLevel" has no waves, so the game warns and plays free play instead. **Continue Saved Run** (on by default) continues your saved chapter run if it's in the same chapter. Runs started from the menu ignore Debug Level.

## Save system (`Scripts/save_game.gd`)

Static class (no autoload, so `project.godot` stays untouched). Loads on first use.

- **File:** `user://save.json`. On Windows: `%APPDATA%\Godot\app_userdata\Azerothtactics\save.json`.
- **Format (version 2; version 1 files load fine):**
  ```json
  {"version": 2,
   "completed_levels": {"ch1_l1": {"best_hp": 90, "times": 2, "first_completed": 1792570290}},
   "unlocks": ["chapter_1_complete"],
   "chapter_run": {"level": "ch1_l2", "hp": 90, "max_hp": 100, "gold": 23, "player_level": 3, "xp": 4,
                   "items": ["quick_bow"],
                   "units": [{"unit": "Knight", "star": 2, "items": ["iron_belt"], "coord": [3, 4]},
                             {"unit": "Cleric", "star": 1, "items": [], "bench": 0}]}}
  ```
  `chapter_run` is what the player carries into `level`; it's written when a level is completed and cleared on defeat or chapter completion. Quitting mid-level and continuing restarts that level with the saved board.
- **API:** `is_level_complete(id)`, `best_hp(id)`, `record_level_complete(id, hp_left, unlocks)`, `has_unlock(id)`, `add_unlock(id)`, `chapter_run()`, `set_chapter_run(carry)`, `clear_chapter_run()`, `reset_progress()`, `data()`.
- **Safety:** writes go to `save.json.tmp` and are then swapped in, so a crash mid-write can't destroy the save. An unreadable file is copied to `save.json.corrupt` and the game starts with empty progress. Loading cleans up odd or older data (`_migrate`), which is where future format versions plug in.
- **Not saved:** progress inside a level (round, shop, board changes since the level started).

## Dev tools and tests

- **Bot playtest:** `Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/bot_playtest.tscn --fixed-fps 60 -- chapter` plays chapter 1 twelve times as real chapter runs and prints how far each got (the main balance check, about a minute). Without arguments it plays each level 10 times from a fresh start; add level paths after `--` for single levels, or `free` for a 15-round free-play smoke test. It uses a throwaway save file.
- **Regression checks:** `... res://tools/campaign_checks.tscn --fixed-fps 60` runs 69 checks in about 20 seconds: board round-trip to JSON, wave provider, enemy placement (authored, locked-tile fallback, overflow), enemy stars/items/synergies, level settings, loss damage, allowed units, top bar text, final-wave rule, end screen buttons, chapter runs (what's carried, restoring it from the save file, HP packs, shop pool, defeat and chapter completion, continuing with Debug Level), save/reload/corrupt/migrate, unlock order, validation, and free play still running a full round. The "Parse JSON failed", ".corrupt", "Patrol ... skipped" and "has no waves" messages in its output are expected (it tests those cases).
- **Class cache:** new `class_name` scripts aren't known to headless runs until Godot rescans. Opening the editor does it; headless, run `--headless --path . --import` once.

## Decisions (confirmed 2026-10-21)

1. The last wave must be won to complete a level (free play still only needs survival).
2. Campaign enemies get synergies; free-play random enemies don't.
3. Enemy tiles still unlock with the player's level; with boards carrying over, the player's level (and so wave size) grows through a chapter.
4. HP starts at 100 and carries across a chapter, with HP packs (`start_heal`, `hp_reward`).
5. `income_bonus` applies from round 1.
6. Levels unlock in one straight line. Boards carry through a chapter and later levels are tuned harder to match.
7. Defeat restarts the chapter (roguelite). The chapter run is saved so you can quit and continue.
8. Unlocks are only recorded for now; they'll be used later.

## Not done (next steps)

- Snapshot provider for PvP (roadmap 9).
- More chapters; balance testing by hand.
