# uv_skills

A collection of reusable skills for UVHS-2 prototyping workflows. Each skill is a self-contained directory (`<name>/SKILL.md` + supporting templates) describing a concrete procedure.

## Skills

| Skill | Description |
|---|---|
| [uv-waveform-probe](./uv-waveform-probe) | 在 UVHS-2 原型平台上抓取并查看某个模块/信号的波形。涵盖完整四阶段流程：fe 注册（probe_net/trigger_net）→ be 落地（trigger_probe -check/-group）→ runtime 采集（capture/upload_uhd）→ uvgui/uvd 查看 .usdb 波形。 |

## How to use

1. Open the skill's `SKILL.md` for the full procedure.
2. Copy the templates under `templates/` into your project's `user_script/` and fill in the `<...>` placeholders.
3. Each entry above lists the signal/probe it covers — pick the one matching your task.
