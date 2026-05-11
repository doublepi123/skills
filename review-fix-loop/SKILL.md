---
name: review-fix-loop
description: |
  主 agent 作为调度器，循环执行 review → fix → review → fix，直到代码没有任何需要修改的问题。
  支持 review 指定文件、git 暂存区、与 master 的 diff、或任意指定的内容范围。
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

### Phase 2: 迭代循环

执行以下循环，直到满足退出条件：

```
while iteration < max_iterations:
    iteration++

    # Step A: Review
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
```

### Phase 3: 生成报告

报告包含以下部分：

```markdown
# Review-Fix Loop 报告

- **目标**: <target>
- **时间**: <timestamp>
- **总迭代次数**: <N>
- **终止原因**: <clean | max_iterations | cycle_detected>

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
