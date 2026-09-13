# 灭霸 BAM 伤害范围修复（用户报的 bug）交接文档

配套：`项目进度备忘.md`（§一 第 8 条已记这条规则；§五 已记本次导出）。

## 1. 问题

**卡面正确口径**：对**灭霸所在地点**的每个英雄造成 **2 点**伤害，然后对**两个相邻地点**的每个英雄各造成 **1 点**伤害。

**旧实现（错的）**：`VillainRules.gd` 的 `_thanos_bam` 写成了

```gdscript
for hid in game.state["hero_ids"]:
    var hl: int = game.state["heroes"][hid]["location"]
    if hl == vpos:
        await game._deal_damage_to_hero(hid, 2)
    else:
        await game._deal_damage_to_hero(hid, 1)   # ✗ 不在灭霸所在地点 → 一律 1 点
```

→ 结果是**整张地图上所有不在灭霸身旁的英雄都挨了 1 点**，包括非相邻地点和正对面，与卡面不符。

## 2. 修复

| 位置 | 内容 |
|---|---|
| `src/rules/VillainRules.gd` **第 143–153 行**（`_thanos_bam`） | 改为只遍历两组：`_heroes_at(game, vpos)` 各 2 点 → `for adj in game._adjacent_locs(vpos): for hid in _heroes_at(game, int(adj))` 各 1 点；写法与既有正确的 `_cull_bam` 一致；循环变量 `int(adj)` 包一下（`_adjacent_locs` 返回 Variant 的类型推断坑）；伤害仍逐次 `await`（保证免伤/转移/无视伤害等触发器顺序正确） |
| `data/villains.json` **第 695 行**（`thanos.bam`） | 「…对**不同地点的**每个英雄造成 1 点伤害」→「…对**两个相邻地点的**每个英雄**各**造成 1 点伤害」 |
| `build/data/villains.json` 第 695 行 | 同上（外置数据同步，SHA256 与 `data/` 一致） |
| 新增 `tests/thanos_bam_test.gd` + `.tscn`（116 行 / **11 项断言**） | 钉住这条口径 |

## 3. 回归断言（`tests/thanos_bam_test`，11 项）

1. 文案：`thanos.bam` 必须含「两个相邻地点」，且**不得**再出现「不同地点」（防文案回退）。
2. 所在地点英雄 **2 点**；3. 顺时针相邻地点英雄 **1 点**；4. 逆时针相邻地点英雄 **1 点**。
5. **非相邻地点英雄完全不被 BAM 打到**（正对面 / 与相邻点隔一格 各一条）← 旧实现下必然失败。
6. 相邻地点恰好 2 个（不是"全部其他地点"）。
7. 边界：相邻两地点都没英雄 → 只有所在地点英雄受 2 点，其余人不受影响。
8. 边界：所有英雄都在灭霸所在地点 → 每人只受 2 点（不会因为"不在相邻地点"再补 1 点）。

**取证：把 `_thanos_bam` 临时改回旧实现再跑同一测试 → 3 项红**（`_testlog/thanos_bam_oldimpl.log`：
三条「非相邻地点英雄不被 BAM 打到 / 边界只有所在地点受伤」全部 FAIL，`ironman hand=3`），
改回新实现后 11/11 绿（`_testlog/thanos_bam_test.log`）——证明这条断言真的能钉住这个 bug。

## 4. 同类问题排查（用户要求 grep 全反派）

**结论：只有灭霸这一处犯了"把相邻写成其他所有地点"的错，已修；另发现 1 处文案与实现不一致（口径不明，未改）。**

| 检查项 | 结果 |
|---|---|
| 所有 `effect.text` / 威胁 / 面板 BAM 文案里出现「相邻」的条目（19 处） | 逐条对照实现：`洗脑`(到达)、`催眠`(奥创)、`灭霸的怜悯`、`净化`(暗夜比邻星)、`斧头摆动`(黑矮星)、`链锤`(常量)、`念力`(乌木侯到达)、`尖叫咪咪`/`月石`(泽莫)、`更好`(沙人) 全部确实用 `_adjacent_locs`；**灭霸面板 BAM 是唯一错的（本次已修）** |
| 全局伤害但文案也写"全体"的（`九头蛇万岁`、`脑袋视线`、`刀刃攻击`兜底、`红骷髅紧急`、`天才智力`、`更强`、克莱文 BAM 等） | 与各自文案一致，属"本来就打全场"，**不是** bug |
| 跨反派**重名威胁卡**（`_trigger_all_threat_bam` 是按卡名 match 的 → 同名不同文本有"一个 case 服务两张卡"的风险） | 只有两组重名，且都已按反派分支：`电光人`（game.gd 第 1919 行起，`state["villain"]=="sandman"` 分支）、`沙人`（第 1856 行起，`"docock"` 分支）。**无遗漏** |
| ⚠️ 待用户裁定（**未改**）：电光人**面板 BAM** | 文案写「对电光人所在地点的**对面地点**，以及**其**相邻两个地点…」，实现 `_electro_bam`（`VillainRules.gd` 第 1226 行附近）用的是「对面地点 + **电光人所在地点的**两个相邻地点」，代码注释明确写着"相邻的两个地点是电光人所在地点的邻居，不是对面地点的邻居"。两者在 6 地点环上打的是**完全不同**的地点（`vpos±1` vs `vpos+3±1`），需要一句裁定：以文案为准还是以现实现为准 |

## 5. 验证（针对性跑，未跑全量 —— 按用户 2026-09 裁定，这属于"规则小改"）

- 相关测试 13 个全绿（`_testlog/thanos_regress_targeted.log`）：
  `thanos_bam_test`(11) / `thanos_bug_test` / `thanos_bug3_test` / `thanos_elim_test` / `thanos_ko_test` /
  `thanos_fix_test` / `setup_thanos_test` / `newvillain_effect_test`(44) / `effect_test`(16) / `iwflow_test` /
  `overflow_once_test`(79，遍历 19 个反派的溢出) / `loki_test` / `zemo_test`(60) —— **FAIL=0 / STUCK=0**。
- 双进程 `devtools/run_net_test.ps1`：**PASS=43 FAIL=0**（`_testlog/thanos_net2.log`）。
  ⚠️ 第一次跑出现 `PASS=4 FAIL=5`（客户端进不了房），原因是上一轮被我中断的全量任务**留下一个孤儿 `MarvelUnited.exe` 进程（PID 3220）占着端口**；杀掉后立刻 43/0 —— 属环境问题，与本改动无关。
- 导出：**19:44**，`MarvelUnited.pck` 791.1MB；`data/` 8 个 JSON → `build/data/` **SHA256 全同**，`build/data/villains.json` 的新文案已生效；
  导出包自检（CWD=build，`-- log-file` 绝对路径，参数 `-- lobby-host`）**退出码 0、`[自检] … 错误=` 为空、SCRIPT ERROR=0**（`_testlog/thanos_boot_final.log`）。

## 6. 未验证 / 注意

- 泽莫那边跑的**全量套件（133 项 FAIL=0）是在本次灭霸改动之前**的状态；灭霸改动之后按用户要求只跑了上面这组针对性测试，**没有重跑全量**。
- `thanos_fix_test` 在无头环境会自我跳过（打印 `TEST PASSED (skipped: 无渲染器)`），所以它这次没有实际断言。
- 电光人面板 BAM 的口径问题（见 §4 末行）**未改**，等裁定。
- 导出包自检日志里仍有两条**既有** ERROR（非本改动）：`Failed to read the root certificate store`、`Parent node is busy adding/removing children`（backtrace `UiKit.goto_scene:113` ← `MainMenu._ready:31`）。
