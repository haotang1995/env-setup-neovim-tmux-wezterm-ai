#!/usr/bin/env python3
"""Interactive skill review tool.

Prompts one skill at a time and records keep/remove decisions.
No MAYBE option.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class Skill:
    skill_id: str
    name: str
    source: str
    description: str
    rel_path: str
    skill_dir: str


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_frontmatter(text: str) -> Tuple[Dict[str, str], str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text

    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text

    fm_lines = lines[1:end]
    body = "\n".join(lines[end + 1 :])

    data: Dict[str, str] = {}
    i = 0
    while i < len(fm_lines):
        line = fm_lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue

        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            i += 1
            continue

        key, value = m.group(1), m.group(2).strip()
        if value in ("|", "|-", ">", ">-"):
            block = []
            i += 1
            while i < len(fm_lines):
                nxt = fm_lines[i]
                if re.match(r"^[A-Za-z0-9_-]+:\s*", nxt):
                    break
                block.append(nxt.strip())
                i += 1
            data[key] = " ".join(part for part in block if part).strip()
            continue

        data[key] = value.strip('"\'')
        i += 1

    return data, body


def detect_source(path: Path) -> str:
    s = str(path)
    if "/superpowers/" in s:
        return "superpowers"
    if "/openai-skills/" in s:
        return "openai-skills"
    if "/tob-skills/" in s:
        return "tob-skills"
    if "/scientific-skills/" in s:
        return "scientific-skills"
    if "/ai-research-skills/" in s:
        return "ai-research-skills"
    if "/.codex/skills/.system/" in s:
        return "codex-system"
    return "other"


def collect_skills(repo_root: Path, include_system: bool) -> List[Skill]:
    skill_files: List[Path] = []

    repo_skills_root = repo_root / "ai-skills" / ".repos"
    if repo_skills_root.exists():
        skill_files.extend(sorted(repo_skills_root.rglob("SKILL.md")))

    if include_system:
        system_root = Path.home() / ".codex" / "skills" / ".system"
        if system_root.exists():
            skill_files.extend(sorted(system_root.rglob("SKILL.md")))

    skills: List[Skill] = []
    for path in skill_files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        frontmatter, body = parse_frontmatter(text)
        name = frontmatter.get("name") or path.parent.name

        description = frontmatter.get("description", "").strip()
        if not description:
            for line in body.splitlines():
                candidate = line.strip()
                if candidate and not candidate.startswith("#"):
                    description = candidate
                    break
        description = re.sub(r"\s+", " ", description).strip()

        if str(path).startswith(str(repo_root)):
            rel = str(path.relative_to(repo_root))
        else:
            rel = str(path)

        source = detect_source(path)
        skill_id = rel

        skills.append(
            Skill(
                skill_id=skill_id,
                name=name,
                source=source,
                description=description,
                rel_path=rel,
                skill_dir=str(path.parent.resolve()),
            )
        )

    # Deduplicate exact path repeats.
    deduped = {s.skill_id: s for s in skills}
    return sorted(deduped.values(), key=lambda s: (s.source, s.name.lower(), s.rel_path))


def load_state(state_path: Path) -> Dict:
    if not state_path.exists():
        return {
            "meta": {
                "version": 1,
                "created_at": now_iso(),
            },
            "decisions": {},
        }

    try:
        return json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raise SystemExit(f"Failed to parse state file: {state_path}")


def save_state(state_path: Path, state: Dict) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state["meta"]["updated_at"] = now_iso()
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def apply_decision_to_agent_dirs(skill: Skill, keep: bool, agent_dirs: List[Path]) -> List[str]:
    """Apply keep/remove to each agent skill directory and return warning messages."""
    warnings: List[str] = []
    source_dir = Path(skill.skill_dir)

    for agent_dir in agent_dirs:
        try:
            agent_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            warnings.append(f"{agent_dir}: failed to create directory ({exc})")
            continue

        target = agent_dir / skill.name

        if keep:
            if target.is_symlink():
                try:
                    if target.resolve() == source_dir:
                        continue
                except OSError:
                    pass
                try:
                    target.unlink()
                except OSError as exc:
                    warnings.append(f"{target}: failed to replace symlink ({exc})")
                    continue
            elif target.exists():
                warnings.append(f"{target}: exists and is not a symlink, skipped")
                continue

            try:
                target.symlink_to(source_dir, target_is_directory=True)
            except OSError as exc:
                warnings.append(f"{target}: failed to create symlink ({exc})")
            continue

        # keep == False
        if target.is_symlink():
            try:
                target.unlink()
            except OSError as exc:
                warnings.append(f"{target}: failed to remove symlink ({exc})")

    return warnings


def format_desc(desc: str, max_len: int = 220) -> str:
    if len(desc) <= max_len:
        return desc
    return desc[: max_len - 3].rstrip() + "..."


def prompt_decision(skill: Skill, idx: int, total: int) -> str:
    print()
    print(f"[{idx}/{total}] {skill.name} ({skill.source})")
    print(f"Path: {skill.rel_path}")
    if skill.description:
        print(f"Function: {format_desc(skill.description)}")
    else:
        print("Function: <no description>")

    while True:
        ans = input("Keep this skill? [y/n/q]: ").strip().lower()
        if ans in {"y", "n", "q"}:
            return ans
        print("Please enter 'y' (keep), 'n' (remove), or 'q' (quit).")


def main() -> None:
    parser = argparse.ArgumentParser(description="Review skills interactively (keep/remove only).")
    parser.add_argument(
        "--state",
        default="ai-skills/skill-decisions.json",
        help="Path to decisions JSON (default: ai-skills/skill-decisions.json)",
    )
    parser.add_argument(
        "--include-system",
        action="store_true",
        help="Include ~/.codex/skills/.system skills in the review list.",
    )
    parser.add_argument(
        "--redo",
        action="store_true",
        help="Re-ask only skills that already have a decision in the state file.",
    )
    parser.add_argument(
        "--no-apply",
        action="store_true",
        help="Only write JSON decisions; do not modify agent skill symlinks.",
    )
    parser.add_argument(
        "--source",
        choices=[
            "superpowers",
            "openai-skills",
            "tob-skills",
            "scientific-skills",
            "ai-research-skills",
            "codex-system",
            "other",
        ],
        help="Review only one source bucket.",
    )
    parser.add_argument(
        "--skill",
        help="Review exactly one skill by name (case-sensitive, matches the skill name field).",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    state_path = (repo_root / args.state).resolve()
    agent_skill_dirs = [
        Path.home() / ".claude" / "skills",
        Path.home() / ".codex" / "skills",
        Path.home() / ".gemini" / "skills",
    ]

    skills = collect_skills(repo_root=repo_root, include_system=args.include_system)
    if args.source:
        skills = [s for s in skills if s.source == args.source]
    if args.skill:
        skills = [s for s in skills if s.name == args.skill]

    if not skills:
        if args.skill:
            raise SystemExit(f"No skill found with name: {args.skill}")
        raise SystemExit("No skills found.")

    state = load_state(state_path)
    decisions = state.setdefault("decisions", {})

    if args.skill:
        # Single-skill mode always asks for that skill, regardless of existing state.
        pending = skills
    elif args.redo:
        # Redo mode only revisits already-decided skills.
        pending = [s for s in skills if s.skill_id in decisions]
    else:
        # Default mode only asks undecided skills.
        pending = [s for s in skills if s.skill_id not in decisions]

    print(f"Total skills in scope: {len(skills)}")
    print(f"Already decided: {len(skills) - len(pending)}")
    print(f"Pending: {len(pending)}")
    print(f"State file: {state_path}")

    if not pending:
        print("Nothing to review.")
        return

    for i, skill in enumerate(pending, start=1):
        ans = prompt_decision(skill, i, len(pending))
        if ans == "q":
            save_state(state_path, state)
            print("Stopped. Progress saved.")
            return

        keep = ans == "y"
        decisions[skill.skill_id] = {
            "name": skill.name,
            "source": skill.source,
            "path": skill.rel_path,
            "skill_dir": skill.skill_dir,
            "keep": keep,
            "updated_at": now_iso(),
        }
        if not args.no_apply:
            warnings = apply_decision_to_agent_dirs(skill=skill, keep=keep, agent_dirs=agent_skill_dirs)
            for warning in warnings:
                print(f"Warning: {warning}")
        save_state(state_path, state)

    keep_count = 0
    remove_count = 0
    for s in skills:
        d = decisions.get(s.skill_id)
        if not d:
            continue
        if d.get("keep"):
            keep_count += 1
        else:
            remove_count += 1

    print()
    print("Review complete.")
    print(f"Keep: {keep_count}")
    print(f"Remove: {remove_count}")
    print(f"Saved to: {state_path}")


if __name__ == "__main__":
    main()
