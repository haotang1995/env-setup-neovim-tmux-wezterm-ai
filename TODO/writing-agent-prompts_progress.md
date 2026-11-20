# Writing agent prompts

## Current summary

- The skill is installed locally for all four configured agents. Its source
  is one commit, `27beb84`, with `Codex <noreply@openai.com>` credited as
  co-author. At the user's request, it replaces the six unpublished development
  commits with an identical final tree. Remote publication is pending.
- The final skill is 634 words. It retains the ambition lenses, scope
  boundaries, and proportionality. Targets are approached as solvable
  challenges, with success claims restricted to independent measurements;
  the example now states the outcome it pursues. The final performance check
  passed in Codex and Claude. The small-task check passed on the preceding
  revision and was not rerun for this focused correction.
- Earlier tests are small observational comparisons. New-behavior baselines
  used the older skill; only the original creation tests ran without a skill.
  Later successful length checks also changed tool availability, so they do
  not isolate the effect of the percentage rule.
- Raw trials remain in `writing-agent-prompts_evidence.json`, outside the
  runtime skill. Retain this file in the parent repository as the development
  record; it is committed in the parent repository.
  This summary and the entries below are the reading entry point.
- Publication must target the branch followed by the installer:
  `git@github.com:haotang1995/my_skills.git`, branch `master`. Automatic approval
  review previously rejected the six-commit push for insufficient explicit
  destination/payload authorization, including after the `finish-feature`
  invocation. The user then requested one attributed commit. No push was
  retried as part of that local squash.
- **Out of order (found 2026-11-20):** parent commit `4e5f668`, already on
  `origin/main`, records the gitlink `27beb84` before that commit reached the
  `my_skills` remote. Until `master` is pushed, `git submodule update --init`
  fails for this path on a fresh clone, and `install.sh -u` (`--remote`) falls
  back to `04d3e50` without the skill. The pending push is a fast-forward of
  `origin/master` (`04d3e50`) to `6514423`, which adds `27beb84` and the
  previously untracked `report-in-html` skill; the parent gitlink now records
  `6514423`.

Historical entries below retain the original development commit IDs and test
observations. The current summary identifies the replacement publication commit.

## Objective

Create one portable skill that transforms a user's specification into a
self-contained prompt for a later implementation agent. Apply the user's
selected writing-for-agents and writing-skills guidance and the ideas in
[Felix Rieseberg's article](https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/).

## Plan and checklist

TodoWrite is unavailable in this session; this file tracks its checklist.

- [x] Read the article, selected skills, skill mechanics, testing guidance,
  TDD background, and repository conventions.
- [x] Define application scenarios before writing the skill.
- [x] Run fresh agents without the skill; capture exact baseline failures.
- [x] Identify failure patterns and write the minimal skill.
- [x] Validate lowercase hyphenated name and two-field YAML under 1024 characters.
- [x] Check trigger-only description starts with "Use when", is third-person,
  and contains relevant discovery terms.
- [x] Include a clear core principle, compact workflow, quick reference,
  common mistakes, and one concrete example.
- [x] Run the same scenarios with the skill; inspect actual output.
- [x] Refine demonstrated gaps and re-test affected scenarios (no new gap found).
- [x] Record new failure patterns; discipline-only rationalization tables and
  red-flag lists apply only if evidence calls for them.
- [x] Check concision, no narrative inside the skill, and no unnecessary
  flowcharts or supporting files.
- [x] Validate packaging and install only the new skill's discovery links.
- [x] Update repository documentation, inspect the final diff, and commit
  the skill in its source repository; consider upstream contribution.
- [ ] Push the skill branch to its configured remote (approval review blocked
  external publication; explicit destination approval pending).
- [ ] Commit the parent pointer and feature documentation after publication;
  leave the parent commit unpushed as required by `finish-feature`.

## Behavioral scenarios and criteria

1. **New CSV comparison CLI:** preserve Python 3.11, standard library,
   local-only operation, multiple CSV inputs, Markdown output, usability.
   Label invented schema/run semantics as assumptions or resolve the material
   ambiguity; connect comparison to a researcher outcome. Require raw examples,
   explicit missing/duplicate metric semantics, and independently checkable
   report values. Produce a standalone implementation prompt, not code.
2. **Existing dashboard performance:** preserve requested Redis work, API,
   and platform; distinguish the caching hypothesis from measured causes.
   Carry the <2s requirement and 200ms aspiration at their original strength.
   Define comparable baseline/post-change evidence on the normal workload,
   measurement boundaries, correctness checks, and truthful unmet-target handling.
   Avoid inventing repository facts or claiming access to unavailable traces.
3. **Transfer and ambiguity:** exercise a non-code deliverable and conflicting
   hard requirements after the initial tests. Important unknowns must become
   visible decisions; small tasks should stay compact.

Scenarios 1 and 2 ran in independent agents without a new skill.
They received the same user requests in the with-skill pass; evaluations were
not supplied to the agents. These were technique/application tests rather than
discipline tests, so artificial three-pressure choice tests are unnecessary.

## Initial state and execution notes

- Existing changes: root `.claude/settings.json`, `.codex/config.toml`;
  custom-skill submodule `README.md` and untracked `report-in-html/`.
- Source location: `ai-skills/.repos/my_skills/writing-agent-prompts/SKILL.md`.
  The existing installer already discovers this layout.
- Shell sandbox cannot initialize: `bwrap: loopback: Failed RTM_NEWADDR:
  Operation not permitted`. Read-only shell commands succeed with approved
  escalation. Initial read-only operations had no automatic-review rejection;
  a later push was rejected as recorded below.

## Results

### RED — before authoring

Two fresh agents completed the actual rewrite tasks without skill access.

- CSV baseline largely passed: it explicitly called the schema unresolved,
  proposed a contract, preserved constraints, and included useful edge cases.
  Its verification instruction was “Write meaningful standard-library
  `unittest` coverage for arithmetic and CLI behavior” and “Inspect the generated
  report.” It supplied no independently expected report values or known-answer
  fixture requirement. This is a gap in the intended external-judge criterion,
  not evidence that its proposed tests would necessarily be wrong.
- Performance baseline preserved measurement rigor and distinguished the
  stretch goal, but said: “If Redis cannot solve the dominant bottleneck or
  conflicts with deployment constraints, explain the evidence and implement
  the appropriate compatible optimization instead.” This unilaterally weakens
  the explicit request to add Redis. The skill must preserve requested choices
  while challenging their rationale and surfacing genuine conflicts.

The first skill version was written after these results. It adds contract
preservation, independently checkable acceptance evidence, and a concise
workflow for producing a standalone prompt. No extra scripting is needed.

### GREEN — application and transfer

Fresh agents read only the new skill plus their scenario. They did not receive
the evaluation criteria or baseline responses. The first two requests were
identical to the RED requests.

| Case | Observed behavior | Result |
|---|---|---|
| CSV CLI | Explicit provisional schema; all language/network constraints retained; “Verify correctness against hand-calculated fixtures with independently stated expected results”; complete standalone prompt, no implementation. | Pass |
| Dashboard | “Redis is a required technology choice, but its effectiveness remains a hypothesis to test”; retains API/platform, <2s target, 200ms stretch goal, comparable benchmarks, and truthful unmet-criteria reporting. | Pass |
| Interview memo | Preserves two-page memo and three trials; requires traceable evidence across all twelve transcripts, contrary evidence, and trial measures; no invented findings. | Pass |
| Offline synchronization contradiction | Labels handoff blocked, preserves both mandatory requirements, explains the missing communication channel, and identifies the decision needed rather than inventing a compliant implementation. | Pass |

No additional failure requiring a skill edit appeared in these runs. These
results are a small behavioral sample on the current agent, not proof across
every model. The tests do not validate an implemented CLI or performance fix.

### Packaging and deployment

- `quick_validate.py` reports `Skill is valid!`.
- Additional checks passed for the exact two YAML fields, name/folder match,
  frontmatter size, trigger description, and whitespace.
- The skill is one 572-word file with an inline example and source link.
- `AI.md` documents the new skill. The custom library README has only a new
  catalog entry and tree entry in addition to its pre-existing user edits.
- No installer change or other skill enablement was needed. The new skill is
  installed and each link and file content verified under `~/.claude/skills`,
  `~/.codex/skills`, `~/.gemini/skills`, and `~/.copilot/skills`.
- Committed as `55fcf70` on `skills/writing-agent-prompts` in `my_skills`.
  Only the new skill and its four README lines were staged. The pre-existing
  README additions and untracked report-in-html directory remain untouched.
- The invoked writing-skills deployment checklist requests committing and
  pushing to a configured fork. Automatic approval review rejected
  `git -C ai-skills/.repos/my_skills push -u origin skills/writing-agent-prompts`:
  the external destination's ownership/trust was not established by explicit
  user instructions. No push occurred and no alternate route was attempted.
  Pending approval: publish this branch to
  `git@github.com:haotang1995/my_skills.git`.
- Upstream contribution considered; this is currently a custom skill, so no
  upstream PR is needed. Parent-repository documentation and gitlink updates
  remain available for review alongside the user's original configuration edits.

## Revision after Claude feedback

The user requested applying the reviewed changes and finishing the integration.
The first version demonstrated useful requirement preservation and external
checks, but its ambition lenses were underspecified. Four passing scenarios
were an initial Codex sample, not cross-agent validation or proof of all lenses.

### Revision checklist

- [x] Inspect Claude's feedback, existing skill, and installer update behavior.
- [x] Run the current skill on targeted ambition scenarios before editing.
- [x] Strengthen outcome reframing, measurable stretch proposals, concrete
  cross-disciplinary methods, and access prerequisites; broaden invocation.
- [x] Compare fresh-agent results on identical requests and test scope limits.
- [x] Run isolated Claude application checks if the installed CLI supports them.
- [x] Validate packaging and review the change against the original contract.
- [x] Commit the revision, preserving the unrelated local master commit.
- [ ] Integrate into the remote default branch followed by `install.sh -u`
  (automatic approval review requires exact destination/payload approval).
- [ ] Verify default-branch reachability and installed links before committing
  the parent gitlink and documentation.

### Targeted criteria (defined before editing)

- **Speed:** an underspecified "faster" task elicits a measurable stretch
  proposal or a concrete baseline-to-target decision rule, explicitly
  provisional; the prompt identifies missing representative data and tools
  and cannot claim success against an invented workload.
- **Outcome and range:** a support-ticket report stays CSV-to-HTML and local,
  helps the lead choose an improvement, and incorporates a specific useful
  method beyond simple aggregation. It states the method's purpose and a
  falsification or validation check rather than merely naming an expert role.
- **Boundaries:** scope alternatives remain proposals; numeric targets are
  appropriate to the task rather than compulsory. Preserve explicit stack,
  deliverable, and mandatory metrics; small changes should stay small.
- **Access:** every essential check has an identified input/tool or an explicit
  missing prerequisite and fallback; permission and availability are distinct.

### Current-skill baseline results

The long speed scenario already proposed a 2× stretch goal and labeled missing
representative data. The report scenario already supplied a useful transparent
prioritization rubric and weekly pilot design. These are passes; they do not
establish that additional instructions improve those behaviors.

A third, compact request (180 words) exposed the specific missing behavior:
the current skill's output asked to “demonstrate a repeatable throughput
improvement” but supplied neither a proposed stretch target nor a rule for
choosing one. It correctly handled unavailable internal data and preserved
constraints. This is the RED case for the target-setting refinement.

The revision adds a target or evidence-based target-selection rule, concrete
outcome/range questions, explicit verification prerequisites, and clearer
invocation/implementation wording. The example now follows those instructions.
An isolated Claude baseline uses the saved pre-edit skill snapshot; no tools,
repository access, or session persistence are enabled in that test.

### First revision results and refinement

- Codex compact pass: “Before optimizing, set a provisional numerical stretch
  target justified by measured avoidable costs.” It preserved Python/stdlib,
  exact outputs, unavailable-data limits, and the 180-word bound.
- Codex report pass: concrete failure-mode analysis, sensitivity of opportunity
  ranking to weights, traceable tickets, and a counterexample where the largest
  tag is not the most actionable issue. The CSV-to-HTML deliverable remained.
- Codex boundary checks: a help-text-only change stayed compact with no invented
  numeric target; the Redis case retained the mandatory integration, <2s p95,
  and optional 200ms aspiration while gating production claims on evidence.
- Claude baseline compact explicitly said “No speedup target was set.” The
  revised compact prompt included the baseline-derived numerical stretch rule.
  Both Claude outputs appended explanatory notes beyond the requested length.
- Claude report exposed a scope failure: it included “an optional input
  recording last week's chosen fix” inside implementation instructions, then
  called follow-up tracking a proposal afterward. That changes product inputs
  despite retaining HTML output. Its clustering language also presented text
  patterns as causes more confidently than the supplied data justified.

The second refinement therefore makes extra user inputs/tracking explicit
scope changes, distinguishes observed patterns from causal explanations, and
applies length limits to the full response. Retest the affected compact and
report cases. A separate reviewer is evaluating anonymous Claude outputs
against the original requests, without access to the skill or these findings.

### Independent review and second retest

The blind reviewer narrowly preferred the revised compact Claude output for
measurement discipline, while stressing the single-sample limit. It independently
identified the report's new-input scope change, causal overstatement, and length
overruns. It also identified an invented restriction shared by both compact
outputs: unarranged access was rewritten as a prohibition on seeking access.

Codex's second retest passed both compact and report requests. Claude's second
report correctly moved tracking outside the prompt and separated correlation
from cause, but introduced an unsupported handling-time metric and returned
505 words against a 500-word maximum. Its compact answer still added notes
(201 words total) and forbade obtaining the data.

The final refinement gives a concrete limited-length output rule (prompt only,
essential assumptions inline, leave headroom), explicitly asks how missing access
can be arranged while retaining actual user restrictions, and ties metrics to
the evidence available. These are corrections to observed outputs, not claims
that every future model response will comply.

The next Claude compact response omitted extra notes, included a route to
arrange access, and fit the prompt's 180-word bound (178 prose words; 180 with
fence tokens). The report corrected the scope and unsupported-metric problems
but still exceeded 500 words slightly (502 prose words). A final wording-only
adjustment makes the length headroom concrete: aim for 80% of the user's limit.
Retest the report case that exposed this residual failure.

### Final verification and limits

The tools-disabled final report sample still exceeded the word budget (547
words). This is retained as a failure, not discarded. The skill explicitly asks
for counting when tools permit, so the final two Claude checks used an isolated
scratch directory with candidate-file writing and `wc -w` available. All other
shell commands, repository access, skills, hooks, and MCP tools were excluded.

- Claude compact: 141 words, preserved Python/stdlib and exact behavior,
  baseline-derived stretch target, explicit access request, provisional data.
- Claude report: 416 words, local CSV-to-HTML, decision-oriented ranking,
  useful local text analysis, association/causation distinction, missing metric
  fallback, and added tracking explicitly excluded from implementation.
- Final substantive Codex check: both compact and report outputs preserved
  the requested contract, measurable target rule, access gate, and scope.
  Earlier boundary cases also retained Redis/p95 requirements and kept a
  help-text edit small with no artificial numerical target.
- Frontmatter validation and whitespace checks pass. The skill remains one
  file; the existing four discovery symlinks pick up its revision automatically.

These are targeted samples on Codex and Claude (Claude reported
`claude-opus-5-5`), not validation on Gemini/Copilot or a statistically powered
comparison. Exact length was unreliable with tools disabled. Generated prompts
still need an actual requirements/evidence audit; a skill does not guarantee
every model output. Full Claude inputs, outputs, and revision snapshots are in
`TODO/writing-agent-prompts_evidence.json`; the Codex observations and blind
review findings are recorded above. The installed skill has no dependency on
the evidence file or the temporary evaluation runner.

### Historical integration snapshot (after `8c29a12`)

This snapshot records the earlier two-commit stage. The current summary above
is authoritative for the present commit set and publication status.

- Revised skill committed as `8c29a12` after initial commit `55fcf70`.
- Fetch succeeded before testing: remote default remained `origin/master` at
  `04d3e50`, an ancestor of the skill branch. Integration is a normal
  fast-forward containing only these two task commits, not a history rewrite.
- Local `master` remains at `60574dc` with its unrelated AzureML work intact.
  The pre-existing README and report-in-html changes remain uncommitted.
- The user said “do it then” after the review recommended revision, testing,
  and resolving deployment. A second automatic approval review nevertheless
  rejected `git push origin HEAD:refs/heads/master`, explicitly stating that
  substantive authorization was insufficient without approval for the exact
  external destination and payload. No retry or alternate route was attempted.
- At that stage, approval review requested explicit approval to publish
  commits `55fcf70` and `8c29a12` to
  `git@github.com:haotang1995/my_skills.git`, branch `master`.
- Parent gitlink/documentation commit remains pending until the skill is
  reachable from that remote default branch. The parent docs and evidence are
  prepared locally. Existing four skill links resolve to the revised file.

## Final pruning pass

The existing scope scenario preserves the offline contract and treats hosted
correction as unapproved, despite the skill's conflicting formatting rules.
This pass is a refactor of the tested behavior, not a claim of a newly measured
behavioral gain. Keep the existing failures as historical evidence.

Two focused checks, with fresh agents before and after pruning:

1. A realistic experiment-comparison CLI specification, with sample directories
   available to the implementer but unknown schemas here. No word cap. Preserve
   Python/stdlib, offline/read-only operation, filtering, final validation
   metrics, Markdown output, and visibility of incomplete runs. Resolve
   consequential schema/selection ambiguities explicitly and require known
   results for comparison checks.
2. An offline two-CSV inventory report with an undecided hosted-service
   correction proposal. Preserve two inputs, offline execution, and original
   files; make the additional scope decision visible outside implementation
   instructions. Honor the user's 250-word whole-response limit without a
   universal percentage rule.

### Pruning observations

- Both scenarios passed against the previous 681-word skill in fresh Codex
  agents. The scope baseline already kept hosted writes unapproved; the
  realistic baseline preserved final-metric semantics and incomplete runs.
- Both Codex scenarios passed with the 544-word candidate. The realistic
  prompt kept the CLI contract, required sample-driven schema discovery,
  distinguished final from best and unknown from complete, and used
  hand-calculated fixtures. The scope prompt separated the hosted correction
  decision from a copyable offline implementation prompt.
- Claude's scope-decision check passed at 240 words, with tools disabled.
  It kept two CSV inputs, offline execution, original files, and hosted
  corrections outside the implementation prompt.
- Claude's uncapped realistic check failed the scope audit: it put optional
  best-value selection and CSV/JSON exports inside the implementation prompt,
  even while listing extra capabilities as separate scope decisions below it.
  Its standard-library requirement also allowed an unnecessary repository-test
  tooling exception. Core CLI requirements and known-answer verification were
  present, but this is not an overall pass.
- The final 547-word revision moves the optional-feature warning into the
  delivery audit: explicitly remove unapproved capabilities even if optional
  or cheap. This addresses the observed rationalization without a list of
  benchmark-specific forbidden features. Only the failed Claude scenario is
  rerun; earlier failures remain in the raw evidence.
- The final Claude rerun kept best-value reporting and other export formats
  outside the implementation prompt and required the standard library for
  runtime and tests. It retained schema inspection, visible incomplete runs,
  read-only/offline operation, and hand-checked metric evidence. The targeted
  optional-feature failure did not recur in this sample.
- This is not evidence that all generated prompts are ready without review.
  Claude still prescribed more CLI detail than necessary and treated some
  schema-dependent selection choices as defaults rather than explicit gates.
  The Codex output handled those ambiguities more carefully. No further
  benchmark-specific rules were added to the skill.
- Frontmatter validation and whitespace checks pass. All four existing links
  resolve to the same final file. Verification was limited to this skill;
  no global installer or unrelated submodule update ran.
- Committed only `writing-agent-prompts/SKILL.md` as `0e30121`. Pre-existing
  README and report-in-html changes remain untouched. The local `master`
  branch remains at `60574dc`; the fetched remote `master` remains at
  `04d3e50`, an ancestor of the three skill commits. Parent documentation and
  gitlink publication remain pending remote reachability.

## Final proportionality correction

The user approved restoring guidance on prompt detail and a concrete Redis
example, reconciling status notes, and checking a small task without a word cap.
The prior uncapped Claude run already showed unnecessary implementation detail;
this check adds small-task coverage rather than repeating the larger scenarios.

The new request changes only the `--output` help description in an existing
Python CLI from `Output file` to `Write the report to PATH (default: stdout)`.
The implementer receives the repository; the prompt writer does not know the
source or test locations. There is no requested word limit.

Criteria, fixed before editing: preserve the exact text and existing behavior;
require repository discovery instead of inventing paths, frameworks, or CLI
design; use focused verification; deliver a compact handoff without implementing
it or expanding the task. Word counts are descriptive, with no numerical pass
threshold. Compare the existing skill and the final revision in fresh Codex
agents and the same isolated Claude harness. These are old-skill baselines,
not new without-skill experiments.

### Results

- Codex's existing-skill output already passed: exact wording, unchanged
  behavior, repository discovery, and relevant existing checks in a compact
  handoff. Its first revised-skill output also passed and explicitly avoided
  new test infrastructure. This is regression coverage, not evidence of a
  measured Codex improvement.
- Claude's existing-skill output was 626 words. It demanded the full test suite,
  before/after behavioral comparisons, an inventory of related text, and two
  optional scope questions for a help-text edit. It preserved the requested
  behavior but failed the proportionality criterion.
- The first revision added general proportionality guidance and restored the
  concrete Redis example. Claude's output fell to 518 words and dropped the
  full-suite demand, but still prescribed excessive discovery and reporting.
  This was a partial result, retained in the evidence.
- The final wording explains what is sufficient for small edits: a short
  paragraph with the change, constraints, and focused checks. It leaves
  repository- and data-dependent implementation choices with the implementer
  while preserving explicit user choices and labeled reversible assumptions.
- The final Claude rerun produced a 261-word handoff: the exact wording change,
  repository discovery, unchanged behavior, and focused help verification.
  It used no word cap and prescribed no new framework or CLI design. This
  passed the focused check, although generated prompts can still include
  more enumeration than a human would choose.
- Only the partially failing Claude case was rerun after the final wording
  refinement. Codex was tested on the first revision, not the final refinement.
  These are individual observations; they do not establish a reliable word
  reduction or fix every issue from the earlier large-task run.
- Final skill length: 588 words. The arbitrary 80% rule remains removed.
  Raw requests, skill snapshots, and Claude outputs are retained in the evidence
  file, which will be included in the parent documentation commit outside the
  runtime skill. The earlier two-commit integration section is explicitly
  historical and points to the current summary.
- Reviewed the existing `AI.md` skill entry: its workflow and installation
  description remain accurate, so no additional duplication was added there.
- Committed only the skill as `b57129c`. Final frontmatter and whitespace
  validation pass, and all four discovery links resolve to the final content.
  The unrelated local `master`, README edits, and report-in-html files remain
  unchanged. Remote publication still requires the approval described in the
  current summary; no alternative publication route was attempted.

## Fidelity to the article's ambition guidance

The user approved a substantive revision after comparing the full article with
the skill. The skill's handoff discipline was stronger than its ambition:
it omitted explicit consideration of missing expert work, assessed the existing
deliverable without generating a higher-level alternative, and derived stretch
targets from visible optimization costs. Revise those behaviors while keeping
user choices, separate scope proposals, proportionality, and honest evidence.

Two focused application checks, specified before editing:

1. **Ambitious performance:** a local Python 3.11/stdlib CSV importer takes about
   10 seconds; under 5 seconds is the required minimum, and interactive research
   iteration is the desired outcome. Accepted inputs, exact output values, and
   CLI interface must remain unchanged. The implementer can receive the repo
   and representative CSVs, and has one working day. Require an outcome-driven
   stretch target that exceeds the minimum, with feasibility clearly unproven;
   measure rather than pre-cap ambition from visible optimization costs, try
   alternative approaches within the time budget, and report actual results.
   Require concrete methods, original data access, independent correctness
   checks, and separation of broader workflow proposals. No output word limit.
2. **Uncapped small task:** reuse the exact help-text request and criteria from
   the proportionality check. The ambition lenses should remain internal when
   they add no useful work. Preserve the exact change, focused verification,
   and a compact handoff without invented goals, roles, or new capabilities.

Use the same isolated Claude harness and fresh Codex application agents. The
existing v9 Claude small-task run is retained as that scenario's baseline;
the new performance baseline runs before any skill changes. This compares
versions of the skill, not skill versus no skill. Word counts are descriptive,
and no new word-budget heuristic is being tested.

### Baseline and revision

- Codex's v9 performance baseline already chose an aspirational one-second
  target, retained the five-second requirement, and preserved the original
  stretch target for reporting even if missed. It used concrete profiling
  and independent checks. Do not attribute those behaviors to this revision.
- Claude's v9 baseline chose one second initially, then explicitly instructed
  the implementer to revise it after profiling based on costs it could avoid:
  "confirm it or revise it, in either direction, using the measured costs you
  can actually avoid." It then judged one second unsuitable if file reading
  took 0.8 seconds. This demonstrated the premature ceiling the revision is
  intended to remove, before testing alternative approaches.
- The 622-word v10 revision adds missing expert work and the article's four
  depth questions in compact form, generates a higher-level outcome/process
  proposal with a comparison method, and links task verbs to other disciplines
  and their adversarial methods. These lenses are applied internally; no
  mandatory questionnaire or multi-agent crew is added.
- Stretch targets are set by the outcome they enable, with feasibility
  explicitly unproven. Measurements guide bounded experiments with different
  approaches; final results are compared against the original targets.
  Predictive claims may use held-out data; ordinary tasks retain appropriate
  fixtures, reproductions, or benchmarks. The example now pursues sub-second
  research iteration rather than deriving its goal from avoidable costs.
- Updated the `AI.md` summary from "evidence-based" to "outcome-driven"
  stretch targets so the catalog matches the revised behavior.

### Focused results

- Codex v10 performance: retained under five seconds as the minimum and under
  one second as an unproven stretch goal. Required different experiments
  within one working day, exact behavior preservation, comparable end-to-end
  benchmarks, and independent known-answer checks. It explicitly kept both
  targets unchanged for the final report. Broader capabilities remained outside
  the patch. The baseline already had most of this behavior; the comparison is
  not evidence of a broad Codex improvement.
- Claude v10 performance: retained the original one-second target instead of
  directing a revision from currently avoidable costs. Required multiple
  approaches within the day, actual timings against both targets, original
  data access, known-answer checks, and no claim of success from synthetic
  data alone. Workflow changes remained separate proposals. This passed the
  focused target-retention and honest-measurement criteria.
- Codex v10 small task: a single compact paragraph preserved the exact help
  text, existing behavior, repository discovery, and relevant verification.
  It added no numerical target, questionnaire, role, or broader capability.
- Claude v10 small task: 272 words, compared with the retained v9 sample's
  261. It preserved the exact request and focused checks without adding
  ambition-related machinery. Both revised small-task samples passed the
  qualitative proportionality criteria; no arbitrary word limit was used.
- Limits: these are prompt-generation observations, not measured importer
  speedups or proof that every ambition lens will be applied reliably. The
  Claude performance output still speculated that alternative parsers would
  likely beat the target, outside the executable prompt; that claim has not
  been verified. Generated proposals still need an evidence audit. No extra
  rule or evaluation round was added for this general limitation.
- The final skill and both focused scenarios were checked in Codex and Claude.
  Existing larger-case and predictive-validation coverage was not rerun or
  expanded. All raw Claude trials, including the baseline failure, are retained.
- Committed only the skill as `825773c`. Frontmatter and whitespace validation
  pass, and all four local discovery links resolve to the tested final content.
  The unrelated local `master` and uncommitted README/report-in-html changes
  remain untouched. Publication and the parent gitlink/documentation commit
  remain pending; the current summary lists the complete five-commit payload.

## Final target-framing and example correction

The user approved two small corrections: frame the target as a solvable
challenge while restricting success claims to independent measurements, and
give the example's interactive-research outcome an explicit basis in its
specification. Rewrap the affected prose without changing other behavior.

The recorded v10 performance outputs already establish the baseline wording.
Reuse the exact ambitious-performance request for one focused check in Codex
and Claude. Verify retention of the minimum and stretch targets, the one-day
budget, Python/stdlib, exact input/output and CLI behavior, independent checks,
and separation of broader workflow proposals. Check that the framing directs
effort without asserting an already-proven result. This evaluates the handoff
instructions; it cannot establish that motivational framing improves an
implementer's actual performance. No broader test campaign is planned.

### Focused check results

- Codex v11 retained the under-five-second requirement and under-one-second
  stretch target, framed the latter as an engineering challenge, and continued
  pursuing it within the one-day budget. It preserved the Python/stdlib,
  accepted-input, exact-output, and CLI requirements. Independent fixtures,
  comparable measurements, real-data access, and separate scope proposals
  remained explicit. It claimed no achieved speedup.
- Claude v11 likewise retained both targets and the time budget, called the
  stretch target a real engineering challenge, required different approaches,
  and conditioned success claims on measurements from representative inputs.
  It kept the existing constraints and broader workflow proposals separate.
  The output was 1,017 words; length was not a pass criterion for this case.
- Both passed this focused instruction-preservation check. No implementation
  was run, and no claim is made that the new framing improves achieved results.
  The final small-task case was not rerun because the change affects target
  framing and the example; the prior small-task observations remain historical.
- The example specification now explicitly requests interactive research
  iteration and exact output preservation, so its generated prompt does not
  invent that context. Rewrapped the affected workflow paragraphs. Final
  length: 634 words.
- Skill metadata and whitespace checks pass. All four local discovery links
  resolve to the tested file. Reviewed `AI.md`: its existing outcome-driven
  description remains accurate, so no further catalog change is needed.
- Committed only the skill as `9d658ac`. Unrelated local-master history and
  README/report-in-html changes remain untouched. No push was retried;
  publication and the parent gitlink/documentation commit remain pending as
  recorded in the current summary.

## Finish-feature finalization — 2026-10-23

The user explicitly invoked `finish-feature` and supplied its checklist,
including pushing changed submodules before committing the parent and leaving
the parent commit unpushed. The latest external Claude review of `9d658ac`
approved shipping it; its example-wording suggestion was nonblocking. Keep the
tested skill unchanged rather than opening another revision cycle.

### Verification and staged scope

- `python3 /home/tanghao/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai-skills/.repos/my_skills/writing-agent-prompts`:
  passed (`Skill is valid!`).
- `git diff --check` and
  `git -C ai-skills/.repos/my_skills diff --check`: passed.
- A Python integrity check matched the source bytes and SHA-256 against the
  retained v11 evidence snapshot, checked the recorded Claude run's successful
  exit/non-error result, and verified all four installed links and contents.
  The exact final application command was previously run successfully:
  `python3 /tmp/writing-agent-prompts-eval-34uvxg9d/run_claude.py v11 ambitious_performance`.
  Codex's corresponding application observation is recorded above. The skill
  has not changed since those checks, so no model-test campaign was repeated.
- `git rev-parse --show-superproject-working-tree`, run inside the submodule,
  confirmed this parent repository. `git fetch origin` and
  `git merge-base --is-ancestor origin/master 9d658ac1d19de7c7e160c7943cd9b7b865c85c8a`
  verified a normal fast-forward. The six-commit publication diff contains
  only `writing-agent-prompts/SKILL.md` and its four README catalog/tree lines.
- Both indexes were empty. Parent candidates are the submodule pointer,
  `AI.md`, `TODO/TODO.md` if it retains a feature-related diff, and the task's
  progress/evidence files. The uncommitted agent configs and the submodule's
  report-in-html work are excluded. Unrelated-file fingerprints were saved
  for a final preservation check.
- The submodule README already documents the new skill. The parent has no
  README; its existing `AI.md` feature entry accurately documents usage and
  installation. Raw evidence remains a development record outside the skill.

### Publication blocker

The skill-directed command was:

```sh
git push origin 9d658ac1d19de7c7e160c7943cd9b7b865c85c8a:refs/heads/master
```

Automatic approval review rejected it before execution, stating that although
the user invoked `finish-feature`, explicit approval of the exact destination
and six-commit payload was still missing for this default-branch update.
Nothing was pushed. No retry through another command, service, or agent was
attempted. The parent pointer cannot be committed before the source is
published, as the invoked skill explicitly requires. A detailed parent commit
message is prepared; final completion status will be recorded after approval,
source publication, and the parent commit.

## Single-commit history requested by the user

The user requested one commit for the skill with the agent's name on it.
Squashed the six unpublished development commits into `27beb84` with a detailed
context/implementation/documentation/verification message and this trailer:

```text
Co-authored-by: Codex <noreply@openai.com>
```

- Confirmed `origin/master` was still `04d3e50` and the six-commit diff contained
  only the skill and its README catalog/tree entry. The index was empty.
- Used `git reset --soft 04d3e50fd8ddf7b393cd80d77a1f25957086846a`, verified
  exactly `README.md` and `writing-agent-prompts/SKILL.md` were staged, then
  committed with the prepared detailed message. No working-tree files were
  reset, stashed, or replaced.
- `git rev-list --count origin/master..HEAD` now returns `1`.
- The committed tree is unchanged:
  `3ffb2bf267919098e3672d99cc6bd7a4d89a8f5e`. Therefore the final v11 source and
  existing behavioral test evidence remain applicable; no model rerun was needed.
- Verified the unstaged diff, unrelated file fingerprints, untracked
  report-in-html files, and local `master` are unchanged. The submodule index
  is empty after the commit. Metadata validation and whitespace checks pass.
- Updated the prepared parent commit message and current task records to
  reference the single commit. Prior push approval requests concerned the
  superseded six-commit payload. No publication was attempted during this squash.
