# AI-Assisted Coding Workflow

**Status:** V0 implemented; live multi-window acceptance test pending  
**Updated:** 2026-08-20  
**Active in-editor transports:** Copilot FIM/NES, CodeCompanion inline, and Claude Code proposals  
**Provider split:** Copilot subscription for T0/T0.5; Claude subscription for T1/T2

## 1. Executive decision

The system should optimize for:

> **accepted useful code per unit of human attention**

The programmer retains ownership of architecture, semantics, and every change
that reaches the real code.

The active workflow uses two deliberately different edit lanes. Obvious local
transformations stay lightweight:

~~~text
select code
    ↓
CodeCompanion + Copilot
    ↓
inline diff
    ↓
accept or reject
~~~

Repository-aware work uses the stronger proposal boundary:

~~~text
select context
    ↓
ask Claude
    ↓
Claude proposes an IDE diff
    ↓
review in Neovim
    ↓
explicit accept or reject
~~~

If that boundary is reliable across multiple Neovim instances in the same
repository, the custom shadow-worktree broker is unnecessary for T1/T2. It
remains the fallback when stronger isolation, pre-display gates, stateless
backends, or provider independence are required.

This document treats proposal safety as a hypothesis to prove, not a property
to assume. <code>claudecode.nvim</code> supplies a native diff UI, but it is not
by itself a filesystem sandbox around Claude Code.

## 2. Existing environment

The workflow must preserve the existing terminal-first environment:

~~~text
local terminal
    ↓
mosh
    ↓
tmux
    ↓
multiple tmux windows
    ↓
one Neovim plus terminals/tools in each work context
~~~

A single repository may be open concurrently:

~~~text
tmux session: project

window 1: pipeline
├── Neovim A
├── pipeline runner
└── logs

window 2: agent
├── Neovim B
├── tests
└── experiment shell

window 3: env
├── Neovim C
└── simulator
~~~

The user moves between these contexts frequently. AI work must return to the
correct editor without selecting a tmux window or stealing foreground focus.

## 3. Identity model

Three identities must remain distinct.

| Concern | Identity |
|---|---|
| Claude IDE connection and proposal destination | Neovim server instance / IDE port |
| Human-visible inbox and notification | tmux window |
| Source and Git operations | repository root |

The repository path is not an editor identity. Several valid Neovim IDE
endpoints can expose the same workspace.

The tmux window is the human interaction unit, but it is not necessarily the
Claude connection identity. If a window ever contains more than one Neovim
pane, each Neovim still requires its own endpoint.

<code>claudecode.nvim</code> creates a WebSocket server on a random port,
writes an IDE lock file, and passes connection information to the Claude
process it launches. V0 therefore launches Claude through each Neovim instance
instead of relying on repository-based external auto-discovery.

Conceptually:

~~~text
pipeline Neovim ── IDE port A ── pipeline Claude
agent Neovim    ── IDE port B ── agent Claude
env Neovim      ── IDE port C ── env Claude
~~~

Same repository, separate editor sessions, separate conversations, and
separate pending proposals.

## 4. Core invariants

### 4.1 Human-owned code

AI output is a proposal until the user explicitly accepts it.

~~~text
Bad:
AI changed my code
    ↓
I must prove it is acceptable

Desired:
AI proposes a change
    ↓
I decide whether it becomes mine
~~~

Acceptance may update a real Neovim buffer while leaving it modified and
unsaved. It never implies a Git commit.

### 4.2 Explicit autonomy levels

Prediction, proposal, and delegation are different operations:

~~~text
T0  prediction
T0.5 selection-scoped inline edit
T1  local proposal
T2  contextual proposal
T3  bounded delegation
~~~

Implementation mechanisms may overlap, but autonomy budgets must not silently
expand.

### 4.3 Non-interrupting completion

A proposal completing in a different tmux window behaves like an inbox item:

~~~text
1:pipeline 🤖
2:agent*
3:env
~~~

It must not run <code>select-window</code>, <code>select-pane</code>, or
otherwise move the user's tmux focus.

The plugin may still change the layout inside the originating, currently hidden
Neovim when it opens a diff. True non-interruption inside the same foreground
Neovim is a separate UX problem and must be measured during V0.

### 4.4 Scope cannot expand silently

If a function-local request requires several files or an architectural change,
the correct response is to stop and request escalation.

~~~text
This appears to require:
- trainer.py
- config.py
- tests/test_trainer.py

Escalate to a contextual proposal or bounded agent?
~~~

### 4.5 Multi-editor coherence

At most one Neovim instance may hold unsaved modifications to a given file at
a time.

Other instances should use <code>autoread</code> and run
<code>checktime</code> on <code>FocusGained</code> and
<code>BufEnter</code>. This repository already has a <code>checktime</code>
autocommand; V0 must verify its behavior rather than add a second competing
implementation.

This rule does not solve proposal staleness. A different Neovim can save a file
after Claude generated a proposal. Cross-instance freshness is therefore a
hard V0 test.

### 4.6 Transport is not isolation

An IDE <code>openDiff</code> flow provides review-before-accept only for edits
that travel through that flow. Claude Code can also possess shell and
filesystem tools.

Therefore V0 must verify that:

1. normal edits are represented as pending IDE diffs;
2. new-file, delete, and rename operations do not bypass review;
3. shell commands cannot modify tracked source without an explicit permission
   or review boundary;
4. reject leaves both the real buffer and filesystem unchanged.

Write-capable Claude tools must not be auto-approved during this experiment.
The exact Claude Code version and permission configuration must be recorded
with the results.

If direct writes can bypass the diff boundary, this architecture fails its
central invariant. The response is stricter permissions, an upstream/plugin
hook, or the shadow-worktree broker—not a documentation disclaimer.

## 5. Assistance hierarchy

| Tier | Meaning | Initial implementation | Target latency | Authority |
|---|---|---|---:|---|
| T0 | Finish what I am typing | Copilot FIM | ideally under 400 ms | Insert suggestion only |
| T0.5 | Transform exactly what I point at | CodeCompanion + Copilot HTTP | roughly 1–5 seconds | Selection-scoped inline diff |
| T1 | Propose the bounded change I point at | Claude Code IDE diff | seconds to tens of seconds | Local proposal |
| T2 | Inspect the repository and propose the correct bounded change | Claude Code IDE diff | tens of seconds | Contextual proposal |
| T3 | Investigate and implement a coherent task | Claude or Codex in an isolated worktree | minutes | Bounded delegation |

### 5.1 T0: completion

Use Copilot FIM when the user is already implementing something and the missing
code is predictable.

~~~text
type
type
Tab
type
Tab
~~~

No prompt, repository exploration, agent, or separate review workflow.

### 5.2 T0.5: fast inline edit

Use CodeCompanion when the desired transformation is obvious and the current
selection or buffer is sufficient context. The inline interaction uses the
Copilot HTTP adapter with model selection set to <code>auto</code>.

It may produce only a local inline proposal. It does not gain repository
search, shell access, test execution, or multi-file authority.

### 5.3 T1: local proposal

T1 is for approximately 10–150 LOC when the user already knows where the
change belongs:

- vectorize this block;
- add the obvious error check;
- simplify this expression;
- add typing to this function;
- remove this unnecessary copy;
- match the style immediately above.

The prompt should constrain the proposal:

~~~text
Vectorize this block.
Preserve dtype, output shape, and masked-entry behavior.
Do not introduce a new abstraction.
Do not change other files.
~~~

### 5.4 T2: contextual proposal

T2 is for known behavior whose correct implementation may require reading
definitions or conventions elsewhere:

- follow masking semantics used in the rollout loss;
- match the repository's established shape handling;
- make this consistent with the configuration path;
- fix the local behavior after inspecting the relevant callers.

T1 and T2 may share the same Claude transport, but they do not share the same
scope contract. T2 permits bounded read/search activity; T1 should remain
local and quick.

### 5.5 T3: bounded delegation

Use T3 only when investigation or multi-file implementation is genuinely
required:

- find why a metric becomes NaN;
- trace a race condition;
- implement a coherent subsystem feature;
- update an end-to-end evaluation path.

T3 runs in an isolated worktree and returns reviewable artifacts.

## 6. Target architecture

~~~text
                                  Neovim
                                     │
              ┌──────────────┬───────┴────────┬──────────────┐
              │              │                │              │
              ▼              ▼                ▼              ▼
        T0 Completion   T0.5 Inline     T1/T2 Proposal    T3 Agent
              │              │                │              │
        Copilot FIM    CodeCompanion    claudecode.nvim   isolated
                             │                │            worktree
                       Copilot HTTP      Claude Code CLI       │
                             │                │                ▼
                       inline diff       native diff      Claude/Codex
                        /      \          /       \
                    accept   reject   accept     reject
~~~

For V0, existing IDE integration is the proposal transport. The custom broker
is a fallback, not a parallel implementation project.

## 7. V0 design: claudecode.nvim

### 7.1 Why this is the first experiment

The plugin already provides:

- a Claude Code terminal inside Neovim;
- per-Neovim WebSocket IDE endpoints;
- visual selection context;
- native proposed-edit diffs;
- explicit accept and deny commands;
- diff-opened and diff-closed User events.

These are the hard interaction primitives the custom broker would otherwise
need to recreate.

### 7.2 Versioning

Pin the plugin to an exact reviewed commit for the PoC. Its events and diff
semantics are part of the design contract, so an unreviewed update must not
change them mid-experiment.

Record:

~~~text
Neovim version
claudecode.nvim commit
Claude Code CLI version
Claude permission configuration
tmux version
~~~

### 7.3 Terminal provider

V0 explicitly uses:

~~~lua
terminal = {
  provider = "native",
}
~~~

Do not leave the provider at <code>auto</code>; deterministic native behavior
is easier to evaluate.

Also retain:

~~~lua
focus_after_send = false
~~~

The user opens or hides the terminal with <code>:ClaudeCode</code>. Hiding must
preserve the process and conversation; that is tested, not assumed.

No tmux popup, nested tmux session, or custom Claude pane manager is introduced
in V0.

### 7.4 Session ownership

The default is one Claude session per Neovim work context that needs one.

~~~text
pipeline Neovim ↔ pipeline Claude
agent Neovim    ↔ agent Claude
env Neovim      ↔ env Claude
~~~

A session need not be started in every window. When it is started, it must be
launched through that Neovim so the endpoint is unambiguous.

### 7.5 User flow

~~~text
1. Work normally.
2. Select the relevant code.
3. Send it to the Claude session.
4. Give a short instruction and scope contract.
5. Continue working or wait.
6. Claude opens a proposed-edit diff in the originating Neovim.
7. Review CURRENT versus PROPOSED.
8. Explicitly accept or reject.
~~~

The plugin documents <code>:ClaudeCodeSend</code>,
<code>:ClaudeCodeDiffAccept</code>, and
<code>:ClaudeCodeDiffDeny</code>. During V0, use the commands or the native
diff's <code>:w</code>/<code>:q</code> behavior before optimizing mappings.

### 7.6 Keymap constraints

The repository already uses:

- visual <code>&lt;leader&gt;p</code> for paste without yanking;
- visual <code>&lt;leader&gt;ai</code> for CodeCompanion inline edits;
- visual <code>&lt;leader&gt;as</code> for Claude context send.

Do not copy conflicting README mappings blindly.

For the PoC:

- use visual <code>&lt;leader&gt;as</code> for
  <code>ClaudeCodeSend</code>;
- use commands or diff-local controls for accept/reject;
- keep <code>&lt;leader&gt;p</code> unchanged.

CodeCompanion uses diff-local <code>ga</code>/<code>gr</code>. Claude proposals
use <code>gda</code>/<code>gdr</code>. The extra <code>d</code> keeps proposal
review distinct from the quick inline lane.

### 7.7 Proposal acceptance semantics

The authoritative review surface is the native Neovim diff:

~~~text
CURRENT                         PROPOSED

existing code                   Claude suggestion
existing code                   Claude suggestion
~~~

Acceptance grants permission to update the real buffer. The buffer may remain
modified and unsaved afterward. Normal editing, testing, and committing remain
human-controlled.

Rejection must leave the original buffer and on-disk file unchanged.

### 7.8 Background lifecycle events

Use the plugin's User events:

~~~text
ClaudeCodeDiffOpened
ClaudeCodeDiffClosed
~~~

The opened event includes file/window metadata. The closed event includes a
human-readable <code>reason</code>; that value is diagnostic and must not be
treated as a stable enum.

An event handler may notify:

~~~text
AI proposal ready in pipeline
~~~

It must not select a tmux pane or window.

### 7.9 Persistent tmux marker

A Boolean marker is insufficient because one Neovim or tmux window may have
multiple unresolved diffs.

Maintain an unresolved-proposal count or idempotent set:

~~~text
ClaudeCodeDiffOpened
    ↓
add proposal key / increment count
    ↓
set window-local @ai_proposal_count

ClaudeCodeDiffClosed
    ↓
remove proposal key / decrement safely
    ↓
clear marker only when count == 0
~~~

Use <code>$TMUX_PANE</code> only as the starting point. Resolve the actual tmux
<code>window_id</code>, then target that window explicitly when setting a
window-local option. Repository basename is never used as identity.

Because the event API has no documented globally stable proposal ID, V0 may use
a best-effort composite of the event's tab name and file path. Handlers must be
idempotent, never allow a negative count, and handle “replaced by new diff” and
<code>:ClaudeCodeCloseAllDiffs</code>.

On Neovim exit or Claude disconnect, clear or reconcile the marker so a crashed
session cannot leave a permanent robot icon.

### 7.10 Freshness across Neovim instances

The dangerous sequence is:

~~~text
Neovim A opens proposal for foo.py
    ↓
Neovim B saves a newer foo.py
    ↓
user accepts stale proposal in A
~~~

V0 must determine whether the plugin prevents or warns about this. A silent
overwrite is a hard failure.

If the plugin lacks a freshness guard, the minimum wrapper records a content
hash when the diff opens and compares it with the current target before
acceptance. Any mismatch blocks acceptance and offers regenerate/discard.

Do not attempt automatic three-way merge in V0.

## 8. V0 proof-of-concept tests

Use one repository and at least two tmux windows:

~~~text
window A: Neovim A + Claude A
window B: Neovim B + Claude B
~~~

### 8.1 Routing correctness

Request different proposals concurrently:

~~~text
A → pipeline edit
B → agent edit
~~~

Required:

~~~text
A proposal appears only in Neovim A
B proposal appears only in Neovim B
~~~

Record the IDE ports and confirm that each plugin-launched Claude process uses
the intended endpoint. Failure is a hard blocker.

### 8.2 Multiple pending proposals

Leave A unresolved, then produce B.

Required:

~~~text
A: pending and reviewable
B: pending and reviewable
~~~

Neither proposal may replace or disconnect the other.

Also test more than one pending diff in a single originating Neovim if the
plugin permits it.

### 8.3 Background arrival

~~~text
launch request in A
    ↓
switch to B
    ↓
A finishes
~~~

Required:

- tmux focus remains on B;
- a lightweight notification appears;
- A's tmux window retains a marker until every A proposal closes.

### 8.4 Terminal lifecycle

~~~text
open Claude
    ↓
work
    ↓
hide Claude
    ↓
continue editing
    ↓
reopen Claude
~~~

Required: same process and conversation remain available.

### 8.5 Proposal safety and bypass tests

For each case, inspect both Neovim buffers and the filesystem before accept and
after reject:

1. normal edit to an existing file;
2. new file;
3. delete;
4. rename;
5. shell-mediated write;
6. edit attempted while Claude write permissions are denied.

Required:

- no tracked source changes before explicit acceptance;
- reject restores or preserves the original state;
- no alternate tool path bypasses proposal review.

Any bypass is a hard blocker for using this as the general T1 proposal layer.

### 8.6 Cross-instance freshness

Open a proposal in A, then save a change to the same target from B.

Required: A cannot silently accept over B's newer content.

Also test external formatting or generation that changes the target while its
proposal is pending.

### 8.7 Marker accounting

Test:

- two opens followed by one close;
- accept;
- reject;
- replacement by a new diff;
- close all diffs;
- Claude disconnect;
- Neovim exit.

Required: the marker is present exactly while the unresolved count is greater
than zero and never becomes negative or permanently stale.

### 8.8 Same-foreground interruption

Continue editing in the same Neovim while Claude works.

Observe whether opening the diff steals Neovim focus or disrupts the active
layout. This is a UX measurement rather than the cross-window hard blocker, but
frequent disruption may justify an inbox buffer or deferred diff presentation.

## 9. V0 measurements

Use the system during real work for approximately one week.

### 9.1 Latency

Classify time from request to reviewable proposal:

~~~text
under 5 s
5–10 s
10–20 s
20–30 s
over 30 s
~~~

The important question is whether the user routinely finishes the change
before Claude returns.

### 9.2 Usefulness

Classify:

~~~text
A  accept essentially as-is
B  useful with a small manual correction
C  reject
~~~

Acceptance/usefulness matters more than generated code volume.

### 9.3 Context benefit

Record whether repository inspection materially improved the answer. If most
successful T1 tasks use only the current selection, route them to the active
T0.5 HTTP inline path and compare latency and usefulness by lane.

### 9.4 Context-switch cost

Observe the cost of:

~~~text
open terminal
prompt
return to code
review
resume work
~~~

Also record how often pending proposals are forgotten.

## 10. V0 success criteria

Continue with <code>claudecode.nvim</code> as the T1/T2 transport only if:

- same-repository multi-Neovim routing is reliable;
- every write-capable path respects proposal-before-write;
- rejection preserves both buffer and filesystem state;
- stale proposals cannot overwrite newer cross-instance edits;
- terminal hide/show preserves sessions;
- background notification does not steal tmux focus;
- marker accounting is correct;
- proposal usefulness and latency are acceptable.

If these conditions hold, do not build the custom broker.

If proposal safety or freshness fails, do not compensate by asking the user to
“be careful.” Add an enforceable boundary or move to the broker.

## 11. V1: proposal policy

V1 adds only friction observed during V0.

### 11.1 Hard gates

Candidates:

- unexpected file;
- file deletion or rename;
- binary change;
- excessive diff size;
- scope violation;
- new dependency;
- syntax failure.

The desired flow is:

~~~text
proposal
    ↓
mechanical policy
    ↓
show only if reviewable
~~~

There is an integration caveat: the documented diff lifecycle event fires
after the diff opens. Closing a bad diff immediately from
<code>ClaudeCodeDiffOpened</code> is not a true pre-display gate.

Before implementing V1, confirm that the pinned plugin exposes a reliable
pre-accept or pre-display interception point. If it does not, choose among:

1. contribute an upstream proposal hook;
2. tolerate post-open automatic denial for small policies;
3. move policy-heavy T1/T2 work to the custom broker.

### 11.2 Soft flags

Flag suspicious changes without rejecting automatically:

~~~text
# type: ignore
noqa
pragma: no cover
TODO / FIXME
deleted assertion
weakened test
new mock
new class
new public API
new dependency
~~~

Show request, changed-file count, diff size, checks, and flags near the review
artifact.

### 11.3 Request metadata

Each pending proposal should retain:

~~~text
request
originating Neovim/tmux window
target file
started time
ready time
baseline content hash
~~~

This is a small per-Neovim pending record, not conversation history.

## 12. Deferred instructions

### 12.1 AI!

Deferred syntax is added only if users repeatedly want to enqueue work without
opening Claude immediately:

~~~python
# AI! Replace this manual normalization with normalize_reward().
~~~

Safe semantics:

~~~text
find marker
    ↓
record instruction and baseline
    ↓
submit proposal while marker remains in real source
    ↓
proposal includes marker removal
    ↓
accept removes marker and applies change
reject/failure leaves marker intact
~~~

Do not remove the real marker before a successful accepted proposal. Doing so
loses the deferred task on backend failure, rejection, crash, or stale result.

Start with an explicit “process nearest AI!” action. Add a save-triggered queue
only after routing, exactly-once behavior, and failure recovery are reliable.

### 12.2 AI?

An optional read-only sibling:

~~~python
# AI? Why is detach() required here?
~~~

It may answer in the Claude terminal or a scratch buffer, but it cannot edit
files. Add it only after the proposal workflow is stable.

## 13. T0.5: fast inline edit

The restored Copilot account makes CodeCompanion the active fast inline lane:

~~~text
T0    Copilot FIM
      under 400 ms

T0.5  CodeCompanion inline
      roughly 1–5 s
      current selection/buffer only

T1    Claude local proposal
      seconds to tens of seconds

T2    Claude contextual proposal
      bounded repository reading

T3    isolated agent
      minutes
~~~

The active backend is the CodeCompanion Copilot HTTP adapter with
<code>model = "auto"</code>. This avoids depending on an account-specific model
ID while still using the restored Copilot model-credit pool. Groq and a local
OpenAI-compatible endpoint remain optional benchmark candidates, not defaults.

Human routing stays explicit:

~~~text
obvious local transform     → T0.5
bounded repo-aware change   → T1/T2
unknown substantial task    → T3
~~~

Do not let the inline tool gain repository search, shell access, multi-file
writes, or autonomous test execution. Escalate instead.

Active mappings respect existing controls:

~~~text
Tab                Copilot FIM
visual <leader>ai  quick inline edit
visual <leader>as  send selection to Claude
diff-local gda     accept Claude proposal
diff-local gdr     reject Claude proposal
AI!                deferred proposal
~~~

## 14. T3: bounded autonomous agents

### 14.1 Isolation

The main worktree is human-owned:

~~~text
MAIN
    human

AGENT WORKTREE A
    disposable Claude/Codex task

AGENT WORKTREE B
    disposable Claude/Codex task
~~~

Full agents do not casually edit the main working tree.

### 14.2 Dirty-state decision

A worktree based on <code>HEAD</code> does not contain current uncommitted
changes. Before launch, explicitly choose:

~~~text
HEAD state
or
snapshot of current dirty state
~~~

If the task depends on “the code I just wrote,” a HEAD-only agent is stale.

### 14.3 Task contract

Give the agent a compact contract:

~~~text
Goal:
Add importance-ratio clipping.

Semantics:
- clip before token reduction
- preserve masked semantics
- disabled behavior remains equivalent

Expected scope:
- trainer/loss.py
- config.py
- tests/test_loss.py

Budget:
under 300 changed LOC

Do not:
- add dependencies
- refactor unrelated code
- introduce a generic abstraction for one use

Stop and report if:
- more than four production files are required
- public API compatibility must change
- a new subsystem is needed
~~~

### 14.4 WIP limit

Optimize for pending semantic review, not process count:

~~~text
foreground:
    human coding + FIM

background:
    at most 1–2 implementation agents needing deep review

additional safe parallel work:
    experiments, profiling, reproductions, benchmarks, investigations
~~~

### 14.5 Review artifact

Review:

~~~text
request
diff
scope
tests
flags
summary
~~~

Do not make the human reconstruct the task from an agent transcript.

## 15. Fallback: shadow-worktree proposal broker

Build the broker only when an observed requirement cannot be enforced through
the IDE integration:

- unreliable same-repo multi-Neovim routing;
- a direct-write path bypasses proposal review;
- cross-instance freshness cannot be enforced;
- policy cannot inspect or deny a proposal at the required point;
- stateless requests are preferable to persistent Claude sessions;
- Codex or another provider is required for T1/T2;
- proposal UI should be decoupled from Claude Code.

### 15.1 Transaction model

~~~text
real repository dirty state at request time
    ↓
snapshot through a temporary Git index
    ↓
reconstruct in isolated shadow worktree
    ↓
write exact BASE_TREE
    ↓
Codex/Claude edits only the shadow
    ↓
write RESULT_TREE
    ↓
tree-to-tree diff
    ↓
hard gates and freshness check
    ↓
Neovim diff
    ↓
explicit accept/reject
~~~

The proposal is:

~~~text
BASE_TREE → RESULT_TREE
~~~

not:

~~~text
HEAD → result
~~~

That distinction removes pre-existing user changes from the AI-only diff.

### 15.2 Broker invariants

- never touch the user's real Git index;
- include staged, unstaged, and relevant untracked non-ignored files;
- recreate the shadow from scratch logically for every transaction;
- preserve pre-existing dirty state exactly;
- reject unsupported mid-merge, rebase, cherry-pick, revert, or bisect states;
- reject or explicitly support sparse checkout, submodules, LFS, and content
  filters;
- scope and diff-budget gates run before human review;
- current real content must match the captured baseline before acceptance;
- failure produces no proposal and never damages the real tree.

Ignored dependencies such as virtual environments, <code>node_modules</code>,
or compiled extensions are not part of <code>BASE_TREE</code>. Verification in
the shadow therefore needs an explicit dependency profile: read-only mounted
or allowlisted artifacts, a reproducible setup step, or checks deferred to the
real environment after acceptance. Never silently assume ignored build state is
present.

## 16. Local models

Do not deploy local models simply because 4×A6000 GPUs exist.

Add a local lane only after measuring:

- cloud latency;
- subscription quota;
- privacy needs;
- provider reliability;
- acceptance rate on real edits.

Benchmark using actual workflow requests:

~~~text
latency
accept as-is
accept with small fix
reject
scope violation
~~~

Keep the interaction contract independent of provider so a local
OpenAI-compatible endpoint can later replace or complement a cloud backend
without changing review authority.

## 17. Rollout

### Phase 0: preserve the baseline

Keep:

~~~text
mosh
tmux
multiple Neovim instances
Copilot FIM
CodeCompanion inline
existing full-agent workflows
~~~

Do not reorganize the entire environment.

### V0: claudecode.nvim PoC

Implement only:

- pinned <code>claudecode.nvim</code>;
- pinned <code>CodeCompanion v19.22.0</code> using Copilot HTTP for T0.5;
- explicit native terminal provider;
- plugin-launched Claude per Neovim instance;
- visual context send;
- proposal diff and accept/reject;
- background notification;
- counted tmux window marker;
- safety and freshness tests.

CodeCompanion is active alongside the V0 Claude proposal experiment. Measure
the lanes separately: T0.5 should receive only obvious selection-scoped edits,
while T1/T2 receives bounded work that benefits from repository context.

### Week 1

Use it naturally without redesigning it daily.

Record:

~~~text
latency bucket
A/B/C usefulness
whether repo context mattered
proposal bypass or stale-state failures
context-switch cost
forgotten pending proposals
~~~

### End-of-week decision

| Observation | Decision |
|---|---|
| Workflow is safe and natural | Keep claudecode.nvim; add only observed V1 policy |
| Claude useful but too slow for tiny edits | Route those edits to active T0.5 CodeCompanion |
| Routing is unreliable | Fix explicit endpoint binding or use broker |
| Direct writes bypass review | Tighten permissions or use broker |
| Cross-instance stale overwrite is possible | Add enforceable hash guard or use broker |
| Native terminal presentation is annoying | Change terminal provider after the proposal model is proven |
| Diff UX is poor | Improve review UX before changing models |
| Workflow is rarely used | Stop investing |

## 18. Failure semantics

| Failure | Required outcome |
|---|---|
| Claude authentication or process failure | No source change; request remains retryable |
| IDE routes to wrong Neovim | Abort V0 architecture decision |
| Proposal rejected | Original buffer and disk remain unchanged |
| Direct write bypasses diff | Treat as safety failure; disable lane |
| Target changes after proposal baseline | Mark stale; regenerate or discard |
| Marker handler misses a close | Reconcile on close-all, disconnect, or Neovim exit |
| Policy hook cannot gate before display | Use post-open denial only if acceptable; otherwise broker |
| Agent worktree lacks needed dirty state | Stop and relaunch from explicit snapshot |
| Broker reconstruction fails | Abort transaction; real tree untouched |

## 19. Non-goals for V0

Do not implement:

~~~text
custom shadow broker
Groq inline route
CodeCompanion chat
AI! or AI?
Tree-sitter scope enforcement
pre-display hard gates
soft reviewer model
tmux popup
nested tmux
local models
multi-model routing
automatic fallback
automatic merge
automatic acceptance
~~~

## 20. Final rule

> **Never let convenience silently increase autonomy.**

If a fast edit begins to require repository search, multiple files, tests,
shell commands, or architectural decisions, do not keep extending the fast
tool. Escalate to the next explicit layer.

The intended mental model is:

~~~text
FIM:
"Finish what I am thinking."

Quick edit:
"Change exactly what I am pointing at."

Proposal:
"Determine the correct bounded change,
but ask before it becomes real."

Agent:
"Investigate this coherent problem independently."

Human:
"Owns architecture, semantics, and commit authority."
~~~

The separation between prediction, proposal, and delegation is the mechanism
that keeps AI assistance fast, reviewable, and unsurprising.

## References

- [claudecode.nvim README](https://github.com/coder/claudecode.nvim/blob/main/README.md)
- [claudecode.nvim protocol documentation](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
