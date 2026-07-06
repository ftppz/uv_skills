# uv_skills

A collection of reusable skills for UVHS-2 prototyping workflows. Each skill is a self-contained directory (`<name>/SKILL.md` + supporting templates) describing a concrete procedure.

## Skills

| Skill | Description |
|---|---|
| [uv-waveform-probe](./uv-waveform-probe) | Capture and view the waveform of a module or signal on the UVHS-2 prototype platform. Covers the full four-stage flow: fe registration (probe_net/trigger_net) → be instantiation (trigger_probe -check/-group) → runtime acquisition (capture/upload_uhd) → viewing the .usdb waveform in uvgui/uvd. |

## How to use

1. Open the skill's `SKILL.md` for the full procedure.
2. Copy the templates under `templates/` into your project's `user_script/` and fill in the `<...>` placeholders.
3. Each entry above lists what it covers — pick the one matching your task.

## Adding a new skill

1. Create a new directory `<skill-name>/` with:
   - `SKILL.md` — frontmatter (`name`, `description`) plus the full procedure.
   - `templates/` — copy-ready script templates with `<...>` placeholders.
2. Add a row to the **Skills** table above using the `description` from the frontmatter so the index stays in sync.
3. Commit and push.
