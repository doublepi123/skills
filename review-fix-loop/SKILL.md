---
name: review-fix-loop
description: |
  主 agent 作为调度器，循环执行 review → fix → review → fix，直到代码没有任何需要修改的问题。
  支持 review 指定文件、git 暂存区、与 master 的 diff、或任意指定的内容范围。
  对超大变更支持按独立文件组拆分并行 review/fix，避免单个 subagent 超出 context 限制。
  内置循环检测机制防止 A→B→A 的 ping-pong 改动，最终产出完整的 review 与修复报告。
allowed-tools:
  - Agent
  - Bash(git *)
  - Bash(shasum *)
  - Bash(cat *)
  - Bash(wc *)
  - Bash(head *)
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Review-Fix Loop

迭代式代码审查与修复：review 和 fix 交替执行，直到代码无缺陷或检测到循环改动为止。

## 参数

调用时用户需提供以下信息（缺失则询问）：

1. **目标 (Target)**: 审查范围，支持以下任一种：
   - `file:<path>` — 单个文件
   - `files:<path1>,<path2>,...` — 多个文件
   - `staged` — git 暂存区变更
   - `diff:master` — 当前分支与 master 的 diff
   - `diff:<branch>` — 当前分支与指定分支的 diff
   - `diff:HEAD~N` — 最近 N 个 commit 的变更
2. **审查焦点 (Focus)** (可选): 安全、性能、可读性、bug、最佳实践等。默认全面审查。
3. **最大迭代次数 (Max Iterations)** (可选): 默认 5。

## 大目标处理

当目标内容明显过大，或单个 subagent 无法在上下文中完整覆盖时，主 agent 应先按“彼此尽量独立的文件组”拆分目标，再并行调度多个 review/fix subagent。

大目标模式是**强制**的：不要把整个大目标塞给一个 review 或 fix subagent，也不要只做单线程轮询。
大目标模式**替代**下面的单目标循环，不是对它的补充。

拆分原则：

- 优先按目录、模块、或不共享实现细节的文件组拆分
- 有强耦合、共享状态、跨文件联动的内容放在同一组
- 任何跨组问题都要在最后的全局收敛阶段再确认一次
- 如果无法安全拆分，退回到单组单轮 review/fix

并行策略：

1. 每个 shard 独立执行 review
2. 对有问题的 shard 独立执行 fix
3. 汇总所有 shard 结果后，再对全局目标执行一次收敛 review
4. 只有当全局收敛 review 通过，才结束流程

大目标模式的固定顺序：

1. 主 agent 先产出 shard plan
2. 并行 review 所有 shard
3. 并行 fix 所有有问题的 shard
4. 将各 shard 的结果合并后做一次全局 review
5. 如果全局 review 仍有问题，回到对应 shard 或创建 cross-shard shard
6. 重复直到全局 clean 或达到最大迭代次数

### 模式选择

- 如果目标很大：直接进入“大目标模式”，不要执行下面的单目标 while 循环
- 如果目标不大：执行下面的单目标 while 循环

### Phase 2: 大目标并行模式（仅当 `target_is_large` 时使用）

1. 主 agent 先按独立性产出 shard plan
2. 并行创建多个 review 子 agent，每个子 agent 只分析自己的 shard
3. 汇总 shard 结果；对有问题的 shard 并行创建多个 fix 子 agent
4. 对所有 shard 的合并结果执行一次全局 review
5. 如果全局 review 仍有问题，回到对应 shard 或创建 cross-shard shard
6. 重复直到全局 clean 或达到最大迭代次数

跨分片问题处理：

- 如果全局收敛 review 发现的问题只影响某个 shard，就把问题回派到对应 shard 再修复一次
- 如果问题跨越多个 shard，创建一个临时的 cross-shard shard，集中处理这些联动问题
- cross-shard shard 也要遵守同样的 review/fix/循环检测规则

## 执行流程

### Phase 1: 初始化

1. 确认目标内容可访问（文件存在、git 仓库可用等）
2. 获取目标内容的初始快照，计算 `shasum` 作为基线
3. 创建报告文件 `.agents/skills/review-fix-loop/reports/$(date +%Y%m%d-%H%M%S).md`
4. 初始化状态：
   - `seen_hashes = []` — 所有出现过的内容哈希
   - `iteration = 0` — 当前迭代轮次
   - `all_issues = []` — 所有发现过的问题
   - `all_fixes = []` — 所有应用过的修复

### Phase 3: 单目标迭代循环（仅适用于未分片目标）

执行以下循环，直到满足退出条件：

```
while iteration < max_iterations:
    iteration++

    if target_is_large and not shard_plan_created:
        按独立性创建 shard_plan，并为每个 shard 建立独立的 review/fix 任务

    # Step A: Review
    if shard_plan_created:
        并行创建多个 review 子 agent，每个子 agent 只分析自己的 shard。
        每个子 agent 必须返回结构化结果：
          - status: "clean" | "issues_found"
          - issues: [{severity, file, line, description, suggestion}]
          - summary: 一句话总结

        将发现的问题按 shard 追加到 all_issues。

        if 所有 shard status 都是 "clean":
            进入全局收敛 review
        else:
            # Step B: 修复
            对有问题的 shard 并行创建多个 fix 子 agent。
            每个 fix 子 agent 只能修改自己 shard 的 issues 中指定的文件和行，不得越界。
            子 agent 返回：
              - fixes: [{issue_index, file, change_summary}]
              - remaining_issues: 修复后仍存在的问题索引列表（如果有无法修复的）

            将修复内容追加到 all_fixes。

            # Step C: 循环检测
            分别计算每个 shard 的修复后哈希，并更新 seen_hashes。

            如果任何 shard 的哈希存在于 seen_hashes 中：
                判定为循环改动，记录发现，退出循环（循环终止）
    else:
        创建 review 子 agent，分析当前目标内容。
        子 agent 必须返回结构化结果：
          - status: "clean" | "issues_found"
          - issues: [{severity, file, line, description, suggestion}]
          - summary: 一句话总结

        将发现的问题追加到 all_issues。

        如果 status == "clean":
            退出循环（成功终止）

        # Step B: 修复
        记录修复前的内容哈希。

        创建 fix 子 agent，修复 review 中发现的问题。
        子 agent 只能修改在 issues 列表中指定的文件和行，不得越界。
        子 agent 返回：
          - fixes: [{issue_index, file, change_summary}]
          - remaining_issues: 修复后仍存在的问题索引列表（如果有无法修复的）

        将修复内容追加到 all_fixes。

        # Step C: 循环检测
        计算修复后目标内容的哈希。

        如果该哈希存在于 seen_hashes 中：
            判定为循环改动，记录发现，退出循环（循环终止）

        将当前哈希加入 seen_hashes。

    # Step D: 全局收敛
    如果 shard_plan_created 且所有 shard 在本轮都 clean 或已修复：
        创建一个全局 review 子 agent，对所有 shard 的合并结果做最后一致性检查。
        如果全局 review clean，退出循环（成功终止）
        如果全局 review 发现问题：
            按影响范围回派到对应 shard，或创建 cross-shard shard 继续处理
```

### Phase 3: 生成报告

报告包含以下部分：

```markdown
# Review-Fix Loop 报告

- **目标**: <target>
- **时间**: <timestamp>
- **总迭代次数**: <N>
- **终止原因**: <clean | max_iterations | cycle_detected>
- **是否分片并行**: <yes/no>
- **shard 数量**: <N>

## Shard Plan
- shard A: <files/modules>
- shard B: <files/modules>

## 迭代历史

### Iteration 1
**Review**: 发现 X 个问题
  - [severity] file:line — description
  - ...
**Fix**: 修复了 Y 个问题
  - file — change_summary
  - ...

### Iteration 2
...

## 最终状态
- 所有发现的问题: <total>
- 已修复: <fixed>
- 无法修复: <unfixable>
- 循环检测触发: <yes/no>

## 最终建议
<对未解决问题的建议或手动干预提示>
```

报告保存路径打印给用户。

## Review 子 Agent 规范

使用 `Agent` 工具创建，类型为 `general-purpose`。Prompt 模板：

```
Review the following code for issues. Focus on: {focus}.

Target: {target_description}
Content:
{current_content}

Return a structured JSON response with this exact format:
{
  "status": "clean" or "issues_found",
  "issues": [
    {
      "severity": "critical" | "high" | "medium" | "low",
      "file": "path/to/file",
      "line": <line_number>,
      "description": "what is wrong",
      "suggestion": "how to fix it"
    }
  ],
  "summary": "one-line summary"
}

Important rules:
- Only flag real, objective issues. Do NOT flag subjective style preferences unless they violate the project's established conventions.
- If the code is genuinely fine, return status "clean" with an empty issues array.
- Be specific about file paths and line numbers.
- Severity definitions:
  - critical: security vulnerability, data loss, crash
  - high: bug that produces wrong results
  - medium: code smell, maintainability issue, missing error handling
  - low: minor style inconsistency, naming suggestions
```

## Fix 子 Agent 规范

使用 `Agent` 工具创建，类型为 `general-purpose`。Prompt 模板：

```
Fix the following issues in the code. ONLY fix the issues listed below.
Do NOT refactor, reformat, or change anything beyond what is needed to address these issues.

Issues to fix:
{issues_json}

Current content:
{current_content}

Return a structured JSON response:
{
  "fixes": [
    {
      "issue_index": <index from input issues array>,
      "file": "path/to/file",
      "change_summary": "what was changed and why"
    }
  ],
  "remaining_issues": [<indices of issues that could NOT be fixed and why>]
}

Critical rules:
- Only touch files and lines listed in the issues. Do NOT make unrelated changes.
- If an issue cannot be safely fixed (e.g., requires broader context, unclear suggestion), list it in remaining_issues.
- Do NOT introduce new issues while fixing.
```

## 循环检测机制

- 对目标内容整体计算 SHA256（使用 `shasum -a 256` 或对目标文件列表分别计算后合并）。
- 每轮修复后重新计算哈希，与 `seen_hashes` 列表比对。
- 哈希匹配意味着修复回到了之前出现过的某个状态，即 A→B→A 循环。
- 一旦检测到循环，立即停止并报告。

### 哈希计算方式

根据目标类型：
- `file:<path>`: `shasum -a 256 <path>`
- `files:<p1>,<p2>`: `cat <p1> <p2> | shasum -a 256`
- `staged` / `diff:*`: `git diff | shasum -a 256`

## 安全约束

- Fix 子 agent 不得修改 review 子 agent 的 prompt 或指令。
- Fix 子 agent 的修改范围严格限制在 issues 中列出的文件和行。
- 每次迭代记录完整的 before/after 哈希，确保可追溯。
- 如果 fix 子 agent 修改了未在 issues 中列出的文件，主 agent 应拒绝该修改并回滚。
