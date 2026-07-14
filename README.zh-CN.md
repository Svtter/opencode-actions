# opencode-actions 中文文档

[English Documentation](README.md)

可复用的 GitHub Actions，用于在其他仓库中安装和运行 OpenCode。

本仓库基于 Apache 2.0 许可证。

## 迁移说明

本项目已不再积极维护。我们已迁移到 [sun-praise/pi-review-agent](https://github.com/sun-praise/pi-review-agent)。

原因是 [issue #278](https://github.com/sun-praise/opencode-actions/issues/278)：opencode 对 litellm/deepseek 记录 `tokens_cache_read = 0`，导致成本统计失真且无法观测 v2 会话恢复带来的节省。该问题需要在上游 opencode 代码中修复，而我们无法修改上游代码。

## 快速开始

在你的 CI.yaml 中写入：

```yaml
- name: Run OpenCode multi-review
  uses: sun-praise/opencode-actions/multi-review@v4
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}

    # 以下密钥只需提供一个即可
    deepseek-api-key: ${{ secrets.DEEPSEEK_API_KEY }}
    zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}
    opencode-go-api-key: ${{ secrets.OPENCODE_GO_API_KEY }}
    litellm-url: ${{ secrets.LITELLM_URL }}
    litellm-api-key: ${{ secrets.LITELLM_API_KEY }}
```

你将获得一个自动化的 PR 审查机器人（默认中文回复，可通过 `language` 输入切换语言）。

或将技能添加到你的项目：

```bash
npx skills add sun-praise/opencode-actions
```

## 包含的 Actions

- `multi-review`：多 agent 并行审查——多个审查者同时运行，协调者将发现综合为一条 PR 评论
- `github-run-opencode`：`opencode github run` 常用工作流的一步封装
- `setup-opencode`：安装 OpenCode，恢复缓存，导出二进制路径
- `run-opencode`：运行 `opencode`，支持 GitHub 网络抖动的重试逻辑

## 语言配置

所有涉及 agent/prompt 的 action（`multi-review`、`github-run-opencode`）均支持 `language` 输入参数，用于控制 agent 的回复语言：

- `zh`（默认）：中文回复
- `en`：英文回复

```yaml
- name: Run OpenCode multi-review (英文)
  uses: sun-praise/opencode-actions/multi-review@v4
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    language: en
```

也可以从仓库变量中读取：

```yaml
- name: Run OpenCode multi-review
  uses: sun-praise/opencode-actions/multi-review@v4
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    language: ${{ vars.OPENCODE_LANGUAGE }}
```

## multi-review

当你需要多个 AI 审查者并行分析 PR、并由协调者综合所有发现为一条评论时使用。

- 通过 OpenCode SDK（`@opencode-ai/sdk`）并行启动 N 个审查者会话
- 内置审查角色（persona）：`quality`、`security`、`performance`、`architecture`、`feature-missing`、`spec-coverage`、`regression-test`、`test-value`
- 协调者会话读取所有审查者输出，生成去重后的综合结果
- 每个审查者的详细输出包含在可折叠的 `<details>` 区块中
- 所有会话共享单个 `opencode serve` 实例（仅需一次 MCP 冷启动）

```yaml
- name: Run OpenCode multi-review
  uses: sun-praise/opencode-actions/multi-review@v4
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    model: deepseek/deepseek-v4-flash
    default-team: "quality:1,security:1,performance:1"
    timeout-seconds: "900"
    coordinator-timeout-seconds: "300"
    deepseek-api-key: ${{ secrets.DEEPSEEK_API_KEY }}
    litellm-url: ${{ secrets.LITELLM_URL }}
    litellm-api-key: ${{ secrets.LITELLM_API_KEY }}
```
## 使用方式

```yaml
uses: sun-praise/opencode-actions/multi-review@v4
uses: sun-praise/opencode-actions/github-run-opencode@v4
uses: sun-praise/opencode-actions/setup-opencode@v4
uses: sun-praise/opencode-actions/run-opencode@v4
```

更多示例请参见 `examples/` 目录。

## 本地验证

```bash
bash tests/test.sh
```
