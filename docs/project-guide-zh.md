# 项目技术指南（中文版）

## 目录

- [1. 项目简介](#1-项目简介)
  - [1.1 项目背景](#11-项目背景)
  - [1.2 本项目的目标](#12-本项目的目标)
  - [1.3 为什么需要同步器](#13-为什么需要同步器)
  - [1.4 本项目与普通复制备份的区别](#14-本项目与普通复制备份的区别)
- [2. 项目功能总览](#2-项目功能总览)
  - [2.1 当前支持的功能](#21-当前支持的功能)
  - [2.2 支持的同步模式](#22-支持的同步模式)
  - [2.3 journal 的作用](#23-journal-的作用)
  - [2.4 冲突检测能力](#24-冲突检测能力)
  - [2.5 enhanced 模式的作用](#25-enhanced-模式的作用)
  - [2.6 已实现选项说明](#26-已实现选项说明)
- [3. 项目目录结构说明](#3-项目目录结构说明)
- [4. 运行环境与依赖要求](#4-运行环境与依赖要求)
  - [4.1 系统环境](#41-系统环境)
  - [4.2 依赖命令](#42-依赖命令)
  - [4.3 如何准备运行环境](#43-如何准备运行环境)
- [5. 运行方法与操作说明](#5-运行方法与操作说明)
  - [5.1 基本命令格式](#51-基本命令格式)
  - [5.2 参数与选项说明](#52-参数与选项说明)
  - [5.3 常见使用示例](#53-常见使用示例)
  - [5.4 如何查看结果](#54-如何查看结果)
  - [5.5 如何运行测试](#55-如何运行测试)
  - [5.6 如何运行演示脚本](#56-如何运行演示脚本)
- [6. 项目工作流详解](#6-项目工作流详解)
- [7. 同步算法与核心判定逻辑详解](#7-同步算法与核心判定逻辑详解)
  - [7.1 什么叫“符合 journal”](#71-什么叫符合-journal)
  - [7.2 简单同步器的核心规则](#72-简单同步器的核心规则)
  - [7.3 enhanced 模式如何减少假冲突](#73-enhanced-模式如何减少假冲突)
  - [7.4 冲突判定情况](#74-冲突判定情况)
  - [7.5 何时执行 A→B 或 B→A](#75-何时执行-ab-或-ba)
  - [7.6 内容相同但元数据不同的处理](#76-内容相同但元数据不同的处理)
  - [7.7 文件类型不同的处理](#77-文件类型不同的处理)
  - [7.8 一侧没有文件时的处理](#78-一侧没有文件时的处理)
- [8. 技术实现剖析](#8-技术实现剖析)
- [9. 代码详解](#9-代码详解)
  - [9.1 参数与输入校验模块](#91-参数与输入校验模块)
  - [9.2 元数据与 journal 模块](#92-元数据与-journal-模块)
  - [9.3 路径扫描模块](#93-路径扫描模块)
  - [9.4 判定与冲突收集模块](#94-判定与冲突收集模块)
  - [9.5 执行与重写 journal 模块](#95-执行与重写-journal-模块)
- [10. 测试体系说明](#10-测试体系说明)
- [11. 冲突、限制与边界情况](#11-冲突限制与边界情况)
- [12. 演示与答辩建议](#12-演示与答辩建议)
- [13. 总结](#13-总结)

---

## 1. 项目简介

### 1.1 项目背景

本项目是一个基于 Bash 的本地文件树同步器，服务于课程项目场景。项目的正式规格来源于仓库中的 `LO03-Projet-2026.pdf`，而仓库中的 `TASK.md` 对需求做了结构化整理。当前实现遵循“尽量忠于题目、遇到歧义时优先保守”的原则。

同步对象不是单个文件，而是同一台机器上的两棵目录树：

- 目录树 `A`
- 目录树 `B`
- 一个记录“上一次成功同步状态”的 `journal` 文件

这个 `journal` 不是普通日志，而是同步决策的依据。

### 1.2 本项目的目标

项目目标是实现一个可以在本地对两棵目录树进行双向同步的 Bash 程序。它需要：

- 扫描 `A` 和 `B` 的相对路径并集
- 比较两侧文件状态和 `journal`
- 在能够安全判断方向时进行同步
- 在无法安全判断时报告冲突，而不是擅自覆盖

同步成功后，程序还需要重写 `journal`，使其反映这次同步成功后的最新一致状态。

### 1.3 为什么需要同步器

如果只是做单向复制，比如简单执行一次 `cp -r`，程序并不知道：

- 哪一侧是“新版本”
- 两侧是否都发生过修改
- 当前差异是内容变化，还是仅仅权限/时间戳变化
- 某个文件缺失到底是“应该删除”，还是“只是另一侧新增”

同步器的价值就在于：

- 它不是盲目复制
- 它会结合“上一次同步成功时的状态”来推断变化方向
- 它会显式报告冲突，避免误覆盖

### 1.4 本项目与普通复制/备份的区别

本项目与常见的“复制”或“备份”有几个本质差异：

1. 它是双向判定的，不是假定某一侧永远是源头。
2. 它依赖 `journal` 来判断变化来源，而不是仅看当前两个目录。
3. 它支持“元数据只同步”的增强判断。
4. 它在歧义情况下优先停止并报冲突，而不是继续执行。

因此，它更接近一个“保守型的状态同步器”，而不是普通的目录复制脚本。

---

## 2. 项目功能总览

### 2.1 当前支持的功能

基于当前代码，项目已经支持以下能力：

- 命令行运行同步器：`bash src/sync.sh [options] DIR_A DIR_B LOG_FILE`
- 检查输入目录和 `journal` 路径是否有效
- 检查依赖命令是否存在
- 扫描 `A` 与 `B` 的相对路径并集
- 对路径进行分类：`missing`、`regular`、`directory`、`unsupported`
- 提取文件元数据：`mode`、`size`、`mtime`
- 读取并解析 `journal`
- 基于 `journal` 和当前文件状态做双向同步判定
- 在增强模式中比较内容并减少假冲突
- 记录动作计划与冲突，再统一执行或统一中止
- 同步成功后原子重写 `journal`

### 2.2 支持的同步模式

当前实际支持两种模式：

#### 1. 普通模式

不加 `--enhanced` 时，程序使用“简单规则”进行同步：

- 元数据完全一致则视为已同步
- 一侧匹配 `journal`、另一侧不匹配时，认为未匹配的一侧发生了变化
- 如果无法安全判断，就报 `regular-conflict`

#### 2. 增强模式

加上 `--enhanced` 后，程序会在两个常规文件出现分歧时进一步比较内容：

- 内容相同但元数据不同，不一定视为真正冲突
- 可以区分“只需同步元数据”和“内容确实冲突”

### 2.3 journal 的作用

`journal` 是本项目最关键的数据结构之一。它记录的是“上一次成功同步后，每个常规文件的状态”。

当前实现中，`journal` 每行格式为：

```text
relative/path<TAB>mode<TAB>size<TAB>mtime
```

它的作用包括：

- 判断某个文件是否仍然处于“旧同步状态”
- 推断是 A 改了还是 B 改了
- 在增强模式中判断“哪一边的元数据仍可信”
- 在成功同步后重建新的基准状态

### 2.4 冲突检测能力

当前实现可以识别以下冲突类型：

- `type-conflict`
  - 同一路径在一侧是目录，另一侧是常规文件

- `presence-conflict`
  - 某一路径只在一侧存在，且程序不能安全推断删除语义
  - 某些单侧目录场景也会保守地归入这一类

- `regular-conflict`
  - 在普通模式下，两个常规文件都不满足安全复制条件

- `content-conflict`
  - 在增强模式下，内容比较后确认两边文件内容不同

- `metadata-only-conflict`
  - 在增强模式下，内容相同，但双方元数据都偏离 `journal`

- `unsupported-type`
  - 遇到当前实现不支持的文件类型

### 2.5 enhanced 模式的作用

增强模式的目标是减少“假冲突”。

典型例子：

- 两个文件内容完全相同
- 但某一侧修改了权限、时间戳

如果只看元数据，程序可能会认为两边发生了冲突；而在增强模式下，程序会先比较内容：

- 如果内容相同，说明不是实质性内容冲突
- 如果只有一侧仍匹配 `journal`，那就只同步元数据
- 如果两边都偏离 `journal`，则报告“元数据冲突”，而不是“内容冲突”

### 2.6 已实现选项说明

当前代码中已经实现的选项只有以下三个：

- `--help`
  - 打印帮助信息并退出

- `--verbose`
  - 输出更详细的信息，包括：
    - 扫描到的相对路径
    - 判定过程
    - 执行动作
    - 基础统计信息

- `--enhanced`
  - 启用增强模式内容比较

当前 **没有** 实现以下常见选项：

- `--dry-run`
- `--force`
- `--delete`
- `--json`

文档中不会把这些未实现功能当作已存在功能描述。

---

## 3. 项目目录结构说明

当前仓库主要结构如下：

```text
src/
  sync.sh
tests/
  run_tests.sh
demo/
  demo.sh
docs/
  design-notes.md
  report-outline.md
  project-guide-zh.md
README.md
TASK.md
LO03-Projet-2026.pdf
```

各文件作用如下：

### `src/sync.sh`

项目的核心同步器脚本。它负责：

- 参数解析
- 环境检查
- 路径扫描
- 读取 `journal`
- 做同步决策
- 记录冲突与动作
- 执行动作
- 重写 `journal`

### `tests/run_tests.sh`

自动化测试脚本。它使用临时目录构造不同同步场景，对输出、返回码、文件内容和元数据进行断言。

### `docs/design-notes.md`

英文设计说明，重点记录：

- `journal` 设计
- 路径扫描
- 决策规则
- 冲突类型
- 两阶段执行模型

### `docs/report-outline.md`

课程报告提纲，用于组织书面提交内容。

### `docs/project-guide-zh.md`

本文件。它是面向学生、队友、答辩准备和交接阅读的中文技术说明文档。

### `demo/demo.sh`

课堂演示脚本，用一个固定流程展示：

- 第一次同步
- 单侧修改传播
- 增强模式下的 metadata-only 同步
- 真实内容冲突

### `README.md`

面向仓库使用者的简要说明文档，适合快速上手。

### `TASK.md`

对课程任务的结构化整理，是当前实现的重要参考依据。

### `LO03-Projet-2026.pdf`

课程原始题目文档，是规范的主来源。

---

## 4. 运行环境与依赖要求

### 4.1 系统环境

当前实现假设运行在 Linux 环境，并使用 Bash 作为执行 shell。

建议环境：

- Linux
- Bash 4 及以上

原因：

- 当前代码使用了 Bash 数组和关联数组
- 使用了 `[[ ... ]]`、`mapfile` 等 Bash 特性

### 4.2 依赖命令

`src/sync.sh` 在启动时会检查以下命令是否存在：

```bash
stat
find
sort
cmp
cp
chmod
touch
mktemp
mv
```

这些命令分别用于：

- `stat`：读取元数据
- `find`：扫描路径
- `sort`：对路径并集排序去重
- `cmp`：比较文件内容
- `cp`：复制文件内容和元数据
- `chmod` / `touch`：做 metadata-only 同步
- `mktemp`：创建临时文件
- `mv`：原子替换 `journal`

测试脚本和演示脚本还会额外使用：

```bash
grep
cat
rm
tail
```

### 4.3 如何准备运行环境

在常见 Linux 发行版中，上述工具通常默认存在。进入仓库根目录后，可直接执行：

```bash
bash src/sync.sh --help
```

如果环境缺失命令，脚本会在启动时用清晰的错误信息终止。

---

## 5. 运行方法与操作说明

### 5.1 基本命令格式

同步器主命令：

```bash
bash src/sync.sh [options] DIR_A DIR_B LOG_FILE
```

其中：

- `DIR_A`：目录树 A
- `DIR_B`：目录树 B
- `LOG_FILE`：`journal` 文件路径

### 5.2 参数与选项说明

#### `DIR_A`

必须是存在的目录。

#### `DIR_B`

必须是存在的目录。

#### `LOG_FILE`

可以是尚不存在的文件，但它的父目录必须存在。

#### `--verbose`

打印详细运行信息，例如：

- 扫描到的路径数
- 每个路径的判定
- 复制动作 / 元数据动作

#### `--enhanced`

启用增强判定逻辑，用于减少内容相同情况下的假冲突。

#### `--help`

打印帮助信息。

### 5.3 常见使用示例

#### 示例 1：最基础的一次同步

```bash
mkdir -p /tmp/treeA /tmp/treeB
printf 'hello\n' > /tmp/treeA/note.txt

bash src/sync.sh /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

这会把 `note.txt` 从 `A` 复制到 `B`，并生成 `journal`。

#### 示例 2：查看详细过程

```bash
bash src/sync.sh --verbose /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

适合调试、答辩讲解或课堂展示。

#### 示例 3：启用增强模式

```bash
bash src/sync.sh --enhanced --verbose /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

适合演示“内容相同但元数据不同”的情况。

### 5.4 如何查看结果

可以从以下几个层面看结果：

1. 终端输出
   - 是否显示 `Synchronization succeeded.`
   - 是否输出 `CONFLICT`

2. 返回码
   - 成功时通常返回 0
   - 发生冲突时返回 2

3. 文件状态
   - 直接用 `cat`、`stat`、`ls -l` 检查 A/B 两侧是否一致

4. `journal`
   - 查看同步后生成或更新的 `journal` 内容

例如：

```bash
cat /tmp/journal.tsv
stat /tmp/treeA/note.txt /tmp/treeB/note.txt
```

### 5.5 如何运行测试

仓库提供了一键测试命令：

```bash
bash tests/run_tests.sh
```

当前测试会逐个打印场景，并在最后输出：

```text
All 8 tests passed.
```

### 5.6 如何运行演示脚本

课堂演示脚本命令：

```bash
bash demo/demo.sh
```

它会自动创建临时目录并展示整个同步过程，无需手动准备环境。

---

## 6. 项目工作流详解

下面按真实执行路径说明一次同步从启动到结束是如何进行的。

### 步骤 1：程序启动与参数解析

用户执行：

```bash
bash src/sync.sh [options] DIR_A DIR_B LOG_FILE
```

进入 `main()` 后，程序首先调用：

- `parse_args`

它会：

- 识别 `--verbose`
- 识别 `--enhanced`
- 识别 `--help`
- 收集 3 个位置参数

如果参数数量不正确，会打印帮助并退出。

### 步骤 2：输入检查

程序调用：

- `validate_inputs`

它会验证：

- `DIR_A` 是否是目录
- `DIR_B` 是否是目录
- `LOG_FILE` 的父目录是否存在

### 步骤 3：依赖命令检查

程序调用：

- `require_dependencies`

如果系统缺少必要工具，比如 `stat` 或 `cmp`，程序会立即退出并给出错误。

### 步骤 4：读取 journal

程序调用：

- `load_journal "$LOG_FILE"`

其行为是：

- 如果 `journal` 不存在，则视为“第一次同步”，不是错误
- 如果存在，则逐行解析
- 忽略空行和以 `#` 开头的注释行
- 把每条记录装入内存中的 Bash 关联数组

此时内存中会得到：

- 路径列表 `JOURNAL_PATHS`
- 路径到 `mode` 的映射
- 路径到 `size` 的映射
- 路径到 `mtime` 的映射

### 步骤 5：扫描 A 和 B 的相对路径并集

程序调用：

- `build_scanned_paths`

它内部会：

1. 分别扫描 `DIR_A` 和 `DIR_B`
2. 得到相对路径列表
3. 合并两侧输出
4. 用 `sort -u` 做排序去重

得到的结果保存在：

- `SCANNED_PATHS`

这个步骤很重要，因为 A 和 B 的目录遍历顺序并不可靠，不能依赖底层文件系统返回顺序一致。

### 步骤 6：初始化动作与冲突收集区

程序使用两个临时文件：

- `TMP_ACTIONS_FILE`
- `TMP_CONFLICTS_FILE`

它们分别保存：

- 后续要执行的动作
- 已发现的冲突

这体现了项目的“两阶段策略”：

先做决定，再统一执行；如果有冲突，就不执行任何动作。

### 步骤 7：遍历并判断每个相对路径

程序调用：

- `decide_all_paths`

它会对 `SCANNED_PATHS` 中的每个相对路径执行：

- `decide_path`

在 `decide_path` 中，程序会先构造：

- `DIR_A/rel`
- `DIR_B/rel`

然后用 `path_kind` 判断两侧的类型：

- `directory`
- `regular`
- `missing`
- `unsupported`

接着根据不同组合进入不同分支。

### 步骤 8：对常规文件执行同步判定

如果某个路径在两侧都是 `regular`，会进入：

- `decide_regular_file_path`

此时：

- 普通模式调用 `simple_regular_file_decision`
- 增强模式调用 `enhanced_regular_file_decision`

这一层会决定：

- 无需动作
- 复制 A→B 或 B→A
- 只同步 metadata
- 记录冲突

### 步骤 9：若有冲突则整体中止

路径遍历结束后，程序检查：

- `conflict_count`

如果大于 0：

- 调用 `print_conflicts`
- 输出所有冲突
- 以返回码 2 退出

注意：此时 **不会** 执行任何复制或元数据修改动作。

### 步骤 10：无冲突时执行动作

如果冲突数为 0，则调用：

- `execute_actions`

它会遍历动作文件中的每条记录，并按类型执行：

- `copy`
- `metadata`

对应底层实现：

- `copy_file_state`
- `apply_metadata_only`

### 步骤 11：重写 journal

动作执行成功后，程序调用：

- `rewrite_journal`

它会：

1. 扫描 `DIR_A` 中所有常规文件
2. 重新生成完整 `journal`
3. 写入临时文件
4. 用 `mv` 原子替换旧 `journal`

之所以以 `DIR_A` 为基准重写，是因为在成功同步后，程序假定 A 与 B 已经保持一致，用其中一侧重建 `journal` 即可。

### 步骤 12：输出结果

成功时，终端输出大致包括：

```text
Synchronization succeeded.
ACTIONS=...
```

若使用 `--verbose`，还会额外输出：

- 路径扫描信息
- 路径判定信息
- 动作信息

---

## 7. 同步算法与核心判定逻辑详解

### 7.1 什么叫“符合 journal”

在当前实现中，一个文件“符合 journal”指的是：

- 路径在 `journal` 中存在
- 当前文件是常规文件
- 当前 `mode` 与 `journal` 一致
- 当前 `size` 与 `journal` 一致
- 当前 `mtime` 与 `journal` 一致

对应代码是：

```bash
journal_entry_matches_file() {
    local rel="$1"
    local path="$2"

    journal_has_entry "$rel" || return 1
    [[ "$(path_kind "$path")" == "regular" ]] || return 1
    [[ "${JOURNAL_MODE["$rel"]}" == "$(file_mode "$path")" ]] || return 1
    [[ "${JOURNAL_SIZE["$rel"]}" == "$(file_size "$path")" ]] || return 1
    [[ "${JOURNAL_MTIME["$rel"]}" == "$(file_mtime "$path")" ]]
}
```

这意味着当前实现中的“符合 journal”是一个 **纯元数据判定**，并不直接比较内容哈希。

### 7.2 简单同步器的核心规则

在普通模式下，如果某路径两侧都是常规文件，则使用以下规则：

1. 如果两边 `mode`、`size`、`mtime` 都相同
   - 视为已同步
   - 不做任何动作

2. 如果 A 符合 `journal`，B 不符合
   - 认为 B 发生了变化
   - 执行 `B -> A` 复制

3. 如果 B 符合 `journal`，A 不符合
   - 认为 A 发生了变化
   - 执行 `A -> B` 复制

4. 否则
   - 报 `regular-conflict`

### 7.3 enhanced 模式如何减少假冲突

增强模式下，程序会先判断内容是否一致：

```bash
if file_contents_match "$path_a" "$path_b"; then
    ...
fi
```

这样可以区分两种完全不同的情况：

- 两边内容真的不同
- 两边内容相同，只是权限/时间戳不一致

对于后者，程序不再简单视为普通冲突，而是进一步区分：

- 是否只是单侧 metadata 漂移
- 是否两侧 metadata 都漂移

这就是增强模式减少“假冲突”的核心机制。

### 7.4 冲突判定情况

当前实现中，会产生冲突的典型情况包括：

#### 1. 类型冲突

同一路径：

- 一边是目录
- 另一边是常规文件

结果：

- `type-conflict`

#### 2. 单侧存在但不能安全推断

例如：

- 一边有文件
- 另一边缺失
- 且该路径已存在于 `journal`

程序不推断“缺失就是删除”，因此报：

- `presence-conflict`

#### 3. 普通模式下两个常规文件都不像“旧状态”

结果：

- `regular-conflict`

#### 4. 增强模式下内容不同

结果：

- `content-conflict`

#### 5. 增强模式下内容相同但双方 metadata 都变了

结果：

- `metadata-only-conflict`

#### 6. 遇到不支持的文件类型

结果：

- `unsupported-type`

### 7.5 何时执行 A→B 或 B→A

当前实现中，复制的典型情况有两类：

#### 1. 一侧新增文件，另一侧缺失，且路径不在 journal 中

例如：

- A 有文件
- B 没有
- `journal` 中不存在该路径

结果：

- 执行 `A -> B`

#### 2. 两侧都有常规文件，但只有一侧符合 journal

例如：

- A 符合 `journal`
- B 不符合

结果：

- 认为 B 是新版本
- 执行 `B -> A`

### 7.6 内容相同但元数据不同的处理

在增强模式下：

#### 情况 1：内容相同且元数据也相同

- 直接成功
- 不做任何动作

#### 情况 2：内容相同，但一侧仍符合 journal

- 只做 metadata 同步
- 不复制整个文件内容

#### 情况 3：内容相同，但两侧都不再符合 journal

- 报 `metadata-only-conflict`

### 7.7 文件类型不同的处理

若某个相对路径在：

- A 中是目录
- B 中是常规文件

或反过来，则当前实现直接报：

- `type-conflict`

不会尝试自动转换类型，也不会删除后重建。

### 7.8 一侧没有文件时的处理

当前实现如实说明如下：

#### 情况 1：一侧有常规文件，另一侧缺失，且该路径不在 journal 中

- 视为新增文件
- 复制到缺失的一侧

#### 情况 2：一侧有常规文件，另一侧缺失，且该路径已经在 journal 中

- 不推断删除含义
- 报 `presence-conflict`

#### 情况 3：一侧有目录，另一侧缺失

- 当前实现采取保守策略
- 报 `presence-conflict`

这里需要特别说明：题目对目录单侧存在时的精细语义并没有在当前代码中做激进推断，因此实现保持保守。

---

## 8. 技术实现剖析

从整体设计上看，`src/sync.sh` 是一个“分层 + 两阶段”的 Bash 脚本。

### 1. 分层思想

代码大致可以分成五层：

1. 参数与输入校验层
2. 元数据与 `journal` 层
3. 路径扫描层
4. 判定层
5. 执行层

这种划分有几个好处：

- 便于阅读和讲解
- 便于测试
- 便于在不改动执行层的情况下修改判定规则

### 2. 为什么采用两阶段策略

当前实现不是“边扫描边修改”，而是：

1. 先扫描并收集所有动作与冲突
2. 如果发现冲突，直接整体中止
3. 如果没有冲突，再统一执行动作

这样设计的原因是：

- 避免一半路径已修改、一半路径未修改的中间状态
- 让冲突语义更清晰
- 更符合“保守同步”的项目目标

### 3. 为什么要原子重写 journal

`journal` 是下一次同步的重要依据。如果写入一半失败，会让后续同步逻辑建立在损坏状态之上。

因此当前实现使用：

- 临时文件写入
- `mv` 替换旧文件

这是一种典型的原子更新模式。

### 4. 为什么要做路径并集扫描

同步问题不是只看 A，也不是只看 B，而是要看：

- A 中出现的路径
- B 中出现的路径

两者并集才是完整的候选集合。否则：

- 某一侧新增的路径会被漏掉
- 某一侧独有的冲突路径会被漏掉

### 5. 为什么不能依赖目录遍历顺序

不同目录的 `find` 输出顺序不一定一致，甚至同一目录在不同环境下也未必稳定。因此当前实现：

- 分别扫描 A 和 B
- 合并输出
- `sort -u`

这样得到一个稳定顺序的路径集合。

### 6. 如何处理带空格路径

当前实现通过以下方式保证对带空格路径友好：

- 所有变量都进行引用
- `find` 输出相对路径，按行处理
- Bash 数组承载路径列表
- `cp`、`chmod`、`touch` 等命令参数均使用 `-- "$path"` 风格

当前实现支持路径中包含空格，但不支持路径中包含 tab，因为 `journal` 使用 tab 作为字段分隔符。

### 7. 如何保留 mode / mtime 等元数据

普通复制时使用：

```bash
cp --preserve=mode,timestamps -- "$src" "$dst"
```

metadata-only 同步时使用：

```bash
chmod --reference="$src" -- "$dst"
touch -r "$src" -- "$dst"
```

这两种实现分别对应：

- 全量文件状态复制
- 只同步元数据

---

## 9. 代码详解

本节不直接贴完整源码，而是按功能模块解释 `src/sync.sh` 的结构、控制流和数据流。

### 9.1 参数与输入校验模块

这一部分的目标是让程序在进入同步逻辑前，先把明显错误拦住。

关键函数：

- `usage`
- `parse_args`
- `validate_inputs`
- `require_dependencies`

代表片段：

```bash
parse_args() {
    local arg
    POSITIONAL_ARGS=()

    for arg in "$@"; do
        case "$arg" in
            --enhanced) ENHANCED_MODE=1 ;;
            --verbose) VERBOSE=1 ;;
            --help) usage; exit 0 ;;
            --*) die "unknown option: $arg" ;;
            *) POSITIONAL_ARGS+=("$arg") ;;
        esac
    done
}
```

这里的设计重点是：

- 先处理选项
- 再收集位置参数
- 参数数量错误时立即退出

控制流上，`main()` 的最前几步都是“先验证，再继续”，这是整个脚本保守风格的一部分。

### 9.2 元数据与 journal 模块

这一层负责两个问题：

1. 怎么描述当前文件状态
2. 怎么读取并使用历史状态

关键函数包括：

- `path_kind`
- `file_mode`
- `file_size`
- `file_mtime`
- `normalized_metadata`
- `parse_journal_line`
- `load_journal`
- `journal_has_entry`
- `journal_entry_matches_file`

代表片段：

```bash
parse_journal_line() {
    local line="$1"
    local rel
    local mode
    local size
    local mtime
    local extra=""

    IFS=$'\t' read -r rel mode size mtime extra <<<"$line"
    ...
    printf '%s\t%s\t%s\t%s\n' "$rel" "$mode" "$size" "$mtime"
}
```

这里的实现思路是：

- 每条 `journal` 记录必须严格符合 4 列格式
- 每列都要做基本合法性检查
- 解析后的数据放进关联数组

数据流上看：

- 文件系统的实时状态通过 `stat` 进入程序
- `journal` 的历史状态通过 `load_journal` 进入内存
- 后续判定函数会同时读取这两部分信息

### 9.3 路径扫描模块

路径扫描模块负责构造同步问题的“全集”。

关键函数：

- `scan_tree_relative_paths`
- `build_scanned_paths`
- `scanned_path_count`

代表片段：

```bash
build_scanned_paths() {
    mapfile -t SCANNED_PATHS < <(
        {
            scan_tree_relative_paths "$DIR_A"
            scan_tree_relative_paths "$DIR_B"
        } | LC_ALL=C sort -u
    )
}
```

这段实现体现出两个核心设计决策：

1. 必须扫描 A/B 并集，而不是单侧
2. 必须排序去重，不能相信底层遍历顺序

### 9.4 判定与冲突收集模块

这是同步器的“大脑”。

关键函数：

- `decide_all_paths`
- `decide_path`
- `simple_regular_file_decision`
- `enhanced_regular_file_decision`
- `decide_regular_file_path`
- `append_action`
- `append_conflict`

#### `decide_path` 的作用

它先根据左右两侧路径的 `kind` 做大类分发：

- `directory:directory`
- `regular:regular`
- `directory:regular`
- `regular:missing`
- `missing:regular`
- `missing:directory`
- `unsupported:*`

代表片段：

```bash
case "$kind_a:$kind_b" in
    directory:directory)
        log "DECISION continue/directories $rel"
        ;;
    regular:regular)
        decide_regular_file_path "$rel" "$path_a" "$path_b"
        ;;
    directory:regular|regular:directory)
        append_conflict "$rel" "type-conflict" "directory versus regular file"
        ;;
esac
```

#### `simple_regular_file_decision` 的作用

它只用：

- 当前 A/B 元数据
- `journal` 匹配关系

来决定：

- 无动作
- 复制 A→B 或 B→A
- 失败并交给上层作为冲突处理

#### `enhanced_regular_file_decision` 的作用

它在 regular 文件分歧时引入内容比较：

```bash
if file_contents_match "$path_a" "$path_b"; then
    ...
fi
```

这里最重要的数据流是：

1. 先看两侧是否都还是“旧状态”
2. 如果不是，再比较内容
3. 如果内容相同，再根据 `journal` 判断是否只同步元数据

这一步正是“减少假冲突”的关键。

### 9.5 执行与重写 journal 模块

判定层不会直接改文件，而是先把动作写入临时动作文件。真正执行动作的是：

- `execute_actions`

代表片段：

```bash
case "$action_type" in
    copy)
        copy_file_state "$src_path" "$dst_path"
        ;;
    metadata)
        apply_metadata_only "$src_path" "$dst_path"
        ;;
esac
```

这里把动作类型限定为：

- `copy`
- `metadata`

便于保持执行层简单稳定。

最后，`rewrite_journal` 会重新扫描同步后的 `DIR_A` 常规文件，并原子替换旧 `journal`。这一步将“本次运行的结果”转化为“下一次运行的基准”。

---

## 10. 测试体系说明

当前测试入口是：

```bash
bash tests/run_tests.sh
```

### 当前有哪些测试

当前脚本覆盖 8 类场景：

1. `identical trees`
2. `only A changed`
3. `only B changed`
4. `both changed with different contents`
5. `both changed with identical contents`
6. `directory/file type conflict`
7. `metadata-only difference with same content`
8. `different traversal order between A and B`

### 每类测试验证什么

#### 1. identical trees

验证：

- 无需动作
- 同步成功
- `ACTIONS=0`

#### 2. only A changed

验证：

- 当 A 偏离 `journal`、B 仍匹配时
- 程序会把 A 的变化复制到 B

#### 3. only B changed

验证：

- 与上一个场景对称
- 程序能正确做 B→A

#### 4. both changed with different contents

验证：

- 增强模式下会报 `content-conflict`

#### 5. both changed with identical contents

验证：

- 内容相同但双方 metadata 都变化时
- 会报 `metadata-only-conflict`

#### 6. directory/file type conflict

验证：

- 类型不一致时会报 `type-conflict`

#### 7. metadata-only difference with same content

验证：

- 增强模式会做 metadata-only 同步，而非整文件复制或误报冲突

#### 8. different traversal order between A and B

验证：

- 路径并集扫描与排序是稳定的
- 不依赖 A/B 的原始遍历顺序

### 如何理解测试结果

测试脚本会逐个打印：

```text
TEST 01: ...
TEST 02: ...
...
```

全部通过时会打印：

```text
All 8 tests passed.
```

如果失败，会直接输出一条形如：

```text
FAIL: ...
```

这样可以快速定位是哪条断言不成立。

### 测试如何覆盖关键场景

这套测试覆盖了当前实现最关键的几类行为：

- 基本成功同步
- 双向变化判定
- 增强模式内容比较
- 冲突分类
- 扫描稳定性

它还没有覆盖所有边界场景，例如：

- 非法 `journal` 格式
- 不支持文件类型
- 单侧目录缺失的更多变体

这些可以作为后续补充方向。

---

## 11. 冲突、限制与边界情况

### 11.1 当前已知限制

当前实现的限制主要包括：

- 不支持符号链接和特殊文件类型
- 不自动推断删除
- 对某些单侧目录情况采取保守冲突策略
- `journal` 不支持路径中包含 tab

### 11.2 不支持的文件类型

`path_kind` 只把路径分成：

- `regular`
- `directory`
- `missing`
- `unsupported`

凡是不属于前两类、又不是缺失的对象，都会进入 `unsupported-type`。

### 11.3 删除语义是否支持

当前实现 **不支持自动删除传播**。

例如：

- 某文件在上一次同步时存在
- 当前只在 A 中存在，在 B 中缺失

程序不会自动理解成“B 把它删掉了，所以 A 也应该删除”，而是会保守地报 `presence-conflict`。

### 11.4 可能的歧义点

当前代码中几个需要特别诚实说明的歧义点是：

1. `journal` 的“符合”定义只比较元数据，不比较内容哈希
2. 对单侧目录的处理比较保守，不做主动创建或删除推断
3. 对“元数据一致但内容不同”的极端情况，普通模式会把它视为已同步

第 3 点尤其值得注意：

当前实现中，`simple_regular_file_decision` 判断“已同步”只看 `mode/size/mtime`，不额外比较内容。这和最严格的内容一致性目标之间存在差异，因此应当在报告和答辩中如实说明。

### 11.5 同步过程中目录被修改的风险

当前实现没有对“运行时文件系统并发变化”做专门加锁。

因此，如果同步过程中用户或其他进程同时修改目录：

- 扫描结果可能与执行时状态不完全一致
- `journal` 可能记录的是运行结束时的最终状态，而不是运行开始时的状态

这是当前 Bash 课程项目实现的合理限制。

### 11.6 还有哪些可改进方向

可改进方向包括：

- 在普通模式下补充“元数据一致但内容不同”的额外保护
- 增加 `--dry-run`
- 增加对非法 `journal` 的专项测试
- 对目录单侧存在的语义做更细分的规则
- 对冲突输出做更人类友好的格式化

---

## 12. 演示与答辩建议

### 12.1 如何向老师展示这个项目

建议不要一开始就讲代码，而是先讲问题模型：

1. 我们不是做单向复制
2. 我们做的是“双目录 + journal”的保守同步
3. 冲突不是失败，而是保护机制

然后再展示实现。

### 12.2 建议演示哪些典型场景

最推荐展示这四类：

1. 初次同步
2. 只改一侧，程序正确传播
3. 内容相同但 metadata 不同，增强模式只同步 metadata
4. 两边内容都改了且不同，程序报冲突

### 12.3 演示顺序建议

建议顺序：

1. 先跑测试，证明项目状态稳定
2. 再跑 `demo/demo.sh`
3. 然后打开 `src/sync.sh` 讲两三个关键函数
4. 最后总结设计亮点与限制

### 12.4 可以重点讲解哪些设计亮点

建议重点讲这些点：

- 路径并集扫描而不是单侧扫描
- `journal` 驱动的变化方向判定
- 增强模式通过内容比较减少假冲突
- 两阶段执行策略避免部分写入
- 原子重写 `journal`

这些点既体现技术实现，也适合口头答辩解释。

### 12.5 演示命令建议

建议在答辩时准备以下命令：

```bash
bash tests/run_tests.sh
```

```bash
bash demo/demo.sh
```

如果要手动展示命令行接口：

```bash
bash src/sync.sh --help
```

---

## 13. 总结

本项目已经完成了一个可运行的 Bash 本地双目录同步器，实现了：

- `journal` 驱动的同步判断
- 路径并集扫描
- 元数据采集
- 普通模式与增强模式
- 冲突识别
- 两阶段执行
- 自动化测试
- 演示脚本

从课程项目角度看，这个实现最有价值的点不是“复制文件”本身，而是：

1. 如何基于 `journal` 推断变化方向
2. 如何在歧义场景下优先保守
3. 如何通过增强模式区分真实内容冲突与 metadata 漂移
4. 如何把 Bash 脚本组织成一个清晰、可讲解、可测试的技术项目

如果读者完整读完本文件，再结合：

- [`src/sync.sh`](/home/fyy/projet/src/sync.sh)
- [`tests/run_tests.sh`](/home/fyy/projet/tests/run_tests.sh)
- [`demo/demo.sh`](/home/fyy/projet/demo/demo.sh)

基本可以完整理解该项目当前的实现、行为边界与后续改进方向。
