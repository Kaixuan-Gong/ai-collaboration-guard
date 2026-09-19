# ai-collaboration-guard

> Collaboration guardrails for **AI coding assistants**. When you and a teammate each work on the same
> project with your own AI, this Skill tells the AI to refresh the real remote state at the moments that
> matter, review the actual diff, and avoid destroying unpushed work.

**Written for beginners, not for Git experts.** Once installed, the AI asks about your situation in plain
language and follows the matching workflow, instead of asking whether you prefer trunk-based or
feature-branch development.

---

## Problems it addresses

When two people (or you plus another AI session) change one project, the damage usually does not come
from mistyped Git commands:

- The remote state you saw when you started is already outdated when you push.
- A single `--force` or `reset --hard` destroys work your teammate just published.
- Half-finished local work is silently discarded during a sync.
- "Merged cleanly" or "tests are green" is reported as done, while the logic is wrong.
- Confusing direct push access with fork-based contribution, so the wrong workflow is used.
- `.env` files and keys get committed by accident.

## How it works: active checks, not a background service

With this Skill installed, **your own AI** does the following at four points:

1. **Before starting.** Run `preflight.sh` for local state, then `remote_check.sh` to fetch the real
   remote state over the network.
2. **Before pushing.** Run `remote_check.sh` again; if the target branch moved, merge it into the feature
   branch first.
3. **Before opening a pull request.** Read the diff, judge logic, interface and data-migration impact,
   record the reasoning, and ask you only about genuine business decisions.
4. **Before merging a teammate's pull request.** Re-check the latest state. GitHub invalidates an old
   approval automatically only when "Dismiss stale pull request approvals" is enabled; regardless of that
   setting, this Skill requires re-reading the newest diff before merging.

**Boundaries, stated honestly:**

- This Skill guides the behavior of a host AI. It is not a background service; without loading and tool
  access, nothing is checked.
- Work your teammate has **not pushed** to the shared remote is invisible to your AI. That is a boundary,
  not a bug.
- It does not install continuous monitoring and does not call a paid external review service.
- Branch protection, required review and required CI exist only after a maintainer configures them in the
  repository; when they are missing, the Skill says so instead of implying enforcement.
- Support for custom scripts and `gh` CLI has not been tested on every AI coding tool.
- The workflow reduces accidental overwrites and skipped review; it does not promise to eliminate every
  textual or logical conflict.

## Seven supported situations

| Your situation | Workflow |
|---|---|
| Starting from nothing, working alone for now | 1 · Solo start |
| Separate computers, teammate can push directly (most common) | 2 · Two machines with a collaborator |
| Two people taking turns on one computer | 3 · Shared computer, sequential |
| Two people or two AIs working in parallel on one machine | 4 · Parallel work with git worktree |
| Teammate has read access only | 5 · Fork and pull request |
| Small project, both sides agree to share one line | 6 · Direct shared branch, with risks stated |
| Marking a version for others to use | 7 · Release tagging |

## Installation

Place the folder in the directory your AI coding tool loads Skills from, for example:

```bash
git clone https://github.com/Kaixuan-Gong/ai-collaboration-guard.git \
  ~/.claude/skills/ai-collaboration-guard
```

Then, inside your project, tell the AI something like "use ai-collaboration-guard to manage collaboration
on this project".

**Requirements:** Git, Bash and Python 3. The `gh` CLI is optional; without it the pull-request status is
reported as UNKNOWN and the AI guides you to check the web interface. Environment prerequisites are in
`references/setup-checklist.md`. Windows needs WSL or Git Bash. Linux support and per-tool script loading
have not been verified.

## Repository layout

```
ai-collaboration-guard/
├── SKILL.md                    # AI entry point: situation routing, safety limits, staged checks
├── scripts/
│   ├── preflight.sh            # Read-only local check; no network access
│   ├── remote_check.sh         # Real fetch; reports OK / ATTENTION / UNKNOWN
│   ├── safe_sync.sh            # Fast-forward only sync that protects uncommitted work
│   └── conflict_check.sh       # Isolated textual merge preview; runs no project code
├── references/
│   ├── safety-rules.md         # Hard safety limits
│   ├── scenarios.md            # Seven collaboration workflows plus onboarding appendices
│   ├── conflict-resolution.md  # Resolving conflicts
│   ├── setup-checklist.md      # Environment prerequisites
│   ├── ai-review-flow.md       # Review duties for the host AI
│   └── gates-setup.md          # Configuring and verifying GitHub gates
└── tests/
    ├── regression.sh           # Behavioral regression suite
    └── independent_probes.py   # Independent acceptance probes
```

## Design principles

- **Plain language first.** Ask about the working setup, not about Git terminology.
- **Ask when it matters.** Missing key facts means asking, not assuming a workflow.
- **Safe by default.** No force push, reset or clean; destructive actions are explained before execution.
- **Check proactively.** Refresh remote state before starting, pushing and merging.
- **No false assurance.** Unverifiable status is reported as UNKNOWN rather than as success.

## Verification and limits

From the repository root:

```bash
bash tests/regression.sh
python3 tests/independent_probes.py .
```

Verified on macOS: 89 regression assertions and 12 independent acceptance checks passed. Tests run only in
temporary Git repositories and never touch production data. Pull-request pagination, malformed responses
and permission failures are exercised through protocol-level simulation; integration against a real
authenticated GitHub account has not been completed in this environment. Linux, Windows and individual AI
tool integrations have not been verified.

- Isolated conflict preview requires Git 2.38 or newer and Python 3. Custom merge attributes return
  LIMITED with a non-zero exit and must not be treated as approval.
- A status of OK means the mechanical query finished, not that the change was reviewed. The AI must still
  read the diff, run applicable tests and confirm real approval and repository protection.
- The Skill does not configure CI or protection rules across projects automatically.
- The scripts are not a sandbox for running untrusted project code. Concurrent Git operations in one
  working directory remain unsupported; use separate worktrees or clones.
- When the default branch or fork target is ambiguous, the AI verifies it first and passes `--base`
  explicitly.

After installing, each person can tell their own AI:

> Use ai-collaboration-guard for this project. Check the existing repository and my teammate's published
> updates first, recommend a suitable workflow, run the checks before starting, pushing and merging, and
> ask me only about business decisions. Do not modify other projects.

## License

[MIT](LICENSE)
