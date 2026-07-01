#!/usr/bin/env bash
#
# gpu-util-monitor.sh — cheap, long-horizon GPU-utilization tracking for a
# Kubernetes namespace.
#
# Unlike a one-shot scorecard, this is built for *sustained* monitoring (e.g.
# a full week, sampled every 2 hours) with near-zero cost and no long-running
# process. A single `sample` execs `nvidia-smi` once in every Running pod and
# appends one CSV row per pod to an append-only log. `report` then aggregates
# the whole log and ranks pods by average GPU-compute utilization — so you can
# see which pods are chronically under-utilizing their GPUs.
#
# The architecture is deliberately stateless-per-run: cron fires `sample`
# every 2h (the time spacing comes from cron, not a `sleep` loop), so nothing
# breaks when your laptop sleeps or an SSH session drops.
#
# Usage:
#   gpu-util-monitor sample            # one snapshot -> append to log
#   gpu-util-monitor report            # aggregate log, rank pods (worst first)
#   gpu-util-monitor report --top 10   # only the 10 least-efficient pods
#   gpu-util-monitor idle              # node-first list of continuous idle streaks
#   gpu-util-monitor idle --min-idle 120   # only streaks >= 120 min
#   gpu-util-monitor install-cron      # every-2h cron job (see --every)
#   gpu-util-monitor uninstall-cron    # remove the cron job
#   gpu-util-monitor status            # cron state + log summary
#
# Namespace resolves from --namespace / -n, else $KNS, else "bonete51".
# Log lives at $GPU_MON_LOG (default ~/gpu-util-logs/<namespace>.csv).

set -euo pipefail

NAMESPACE="${KNS:-bonete51}"
EVERY_HOURS=2
TOP=0
MIN_IDLE=60
CMD="${1:-}"
[[ $# -gt 0 ]] && shift || true

# ── Arg parsing (shared across subcommands) ───────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2;;
    --every)        EVERY_HOURS="$2"; shift 2;;
    --top)          TOP="$2"; shift 2;;
    --min-idle)     MIN_IDLE="$2"; shift 2;;
    -h|--help)      CMD="help"; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

LOG="${GPU_MON_LOG:-${HOME}/gpu-util-logs/${NAMESPACE}.csv}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── Colour helpers (disabled when piped) ──────────────────────────────────────
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; YEL=$'\033[0;33m'; GRN=$'\033[0;32m'
  CYN=$'\033[0;36m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=''; YEL=''; GRN=''; CYN=''; BLD=''; RST=''
fi

usage() {
  sed -n '3,30p' "$SELF" | sed 's/^# \{0,1\}//'
  exit 0
}

LOG_HEADER="epoch,iso,pod,node,avg_gpu_util,avg_mem_util,num_gpus,gpu_type,mem_used_mib,mem_total_mib"

# ── sample: one snapshot, append one CSV row per GPU pod ──────────────────────
do_sample() {
  mkdir -p "$(dirname "$LOG")"
  # Create the log, or migrate an older-schema log (pre-`node` column) out of the
  # way so the CSV columns stay consistent for the readers.
  if [[ ! -f "$LOG" ]]; then
    echo "$LOG_HEADER" > "$LOG"
  else
    local first; IFS= read -r first < "$LOG" || first=""
    if [[ "$first" != "$LOG_HEADER" ]]; then
      local bak="${LOG%.csv}.$(date +%Y%m%d%H%M%S).old.csv"
      mv "$LOG" "$bak"
      echo "Log schema changed; archived old log -> ${bak}" >&2
      echo "$LOG_HEADER" > "$LOG"
    fi
  fi

  local epoch iso pods pod
  epoch=$(date +%s)
  iso=$(date '+%Y-%m-%dT%H:%M:%S')

  mapfile -t pods < <(kubectl get pods -n "$NAMESPACE" --no-headers \
    --field-selector=status.phase=Running 2>/dev/null | awk '{print $1}')

  # pod -> node map (one call) so idle time can be attributed to a physical node.
  declare -A NODE=()
  local pn nn
  while read -r pn nn; do
    [[ -n "$pn" ]] && NODE[$pn]="${nn:--}"
  done < <(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' 2>/dev/null)

  local logged=0
  for pod in "${pods[@]}"; do
    local out
    out=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
      nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,gpu_name \
      --format=csv,noheader,nounits 2>/dev/null) || continue   # no GPU / no nvidia-smi

    local n=0 tg=0 tm=0 mu=0 mt=0 gtype=""
    while IFS=',' read -r gu mem mused mtotal gname; do
      [[ -z "${gu// }" ]] && continue
      gu=${gu// }; mem=${mem// }; mused=${mused// }; mtotal=${mtotal// }
      gtype=$(echo "$gname" | xargs)
      tg=$((tg + gu)); tm=$((tm + mem)); mu=$((mu + mused)); mt=$((mt + mtotal))
      n=$((n + 1))
    done <<< "$out"
    (( n == 0 )) && continue

    printf '%s,%s,%s,%s,%d,%d,%d,%s,%d,%d\n' \
      "$epoch" "$iso" "$pod" "${NODE[$pod]:--}" "$((tg/n))" "$((tm/n))" "$n" "$gtype" "$mu" "$mt" >> "$LOG"
    logged=$((logged + 1))
  done
  echo "${iso}  ns=${NAMESPACE}  sampled ${logged}/${#pods[@]} running pods -> ${LOG}" >&2
}

# ── report: aggregate the log, rank pods by mean GPU util (worst first) ────────
do_report() {
  [[ -f "$LOG" ]] || { echo "No log yet at $LOG (run 'gpu-util-monitor sample' first)." >&2; exit 1; }
  TOP="$TOP" NS="$NAMESPACE" python3 - "$LOG" <<'PY'
import csv, os, re, sys
from collections import defaultdict

path = sys.argv[1]
top  = int(os.environ.get("TOP", "0"))
ns   = os.environ.get("NS", "")

IDLE_THRESH = 5   # a sample with GPU util < this% counts as "idle"

agg = defaultdict(lambda: {"gpu":0,"mem":0,"n":0,"idle":0,"gpus":0,"type":"",
                           "mu":0,"mt":0,"first":None,"last":None})
stamps = set()
with open(path, newline="") as f:
    for r in csv.DictReader(f):
        p = agg[r["pod"]]
        stamps.add(r["iso"])
        gu = int(r["avg_gpu_util"])
        p["gpu"]  += gu
        p["mem"]  += int(r["avg_mem_util"])
        p["mu"]   += int(r["mem_used_mib"])
        p["mt"]   += int(r["mem_total_mib"])
        p["n"]    += 1
        p["idle"] += 1 if gu < IDLE_THRESH else 0
        p["gpus"]  = int(r["num_gpus"])
        p["type"]  = r["gpu_type"]
        p["first"] = r["iso"] if p["first"] is None else p["first"]
        p["last"]  = r["iso"]

rows = []
for pod, p in agg.items():
    if p["n"] == 0: continue
    rows.append((p["gpu"]/p["n"], p["mem"]/p["n"], pod, p["gpus"], p["type"],
                 p["n"], p["mu"]/p["n"], p["mt"]/p["n"], p["first"], p["last"],
                 100*p["idle"]/p["n"]))
rows.sort(key=lambda x: x[0])   # worst (lowest avg GPU util) first
if top > 0:
    rows = rows[:top]

# ── styling helpers ───────────────────────────────────────────────────────────
COLOR = sys.stdout.isatty()
def c(s, code):   return f"\033[{code}m{s}\033[0m" if COLOR else s
BOLD, DIM = "1", "2"
GREEN, YELLOW, RED, CYAN, GREY = "38;5;42", "38;5;220", "38;5;203", "38;5;44", "38;5;244"

def tone(pct):                       # colour code for a utilisation value
    return GREEN if pct >= 60 else (YELLOW if pct >= 25 else RED)

BLOCKS = "▏▎▍▌▋▊▉"                   # 1/8 .. 7/8 partial cells
def ubar(pct, width=16):
    pct = max(0.0, min(100.0, pct))
    eighths = int(round(pct / 100.0 * width * 8))
    full, rem = divmod(eighths, 8)
    s = "█" * full + (BLOCKS[rem - 1] if rem else "")
    s += "░" * (width - len(s))
    return c(s, tone(pct))           # visible width == width

def dot(pct):
    return c("●", tone(pct))

# ── column layout (plain widths; bars/values coloured but same width) ─────────
W_POD, W_BAR, W_TYPE = 24, 16, 8
HEADER = (f" {'POD':<{W_POD}}  {'UTILISATION':<{W_BAR}}  {'GPU':>4} {'MEM':>4} "
          f"{'IDLE':>5}  {'GPUs':>4} {'n':>4}  {'TYPE':<{W_TYPE}}")
WIDTH = len(HEADER)

def rule(l, m, r):  return l + "─" * (WIDTH - 2) + r
def panel(txt):                       # one line inside the title box
    vis = len(re.sub(r"\033\[[0-9;]*m", "", txt))
    return "│ " + txt + " " * (WIDTH - 3 - vis) + "│"

n_rounds = len(stamps)
win = f"{min(stamps)}  →  {max(stamps)}" if stamps else "no samples yet"

print(rule("╭", "─", "╮"))
print(panel(c("GPU Utilisation Report", BOLD) + c(f"   ns={ns}", CYAN)))
print(panel(c(f"{len(agg)} pods · {n_rounds} sample rounds · {win}", DIM)))
print(rule("╰", "─", "╯"))
print()
print(c(HEADER, BOLD))
print(c("─" * WIDTH, GREY))

for g, m, pod, gpus, typ, n, mu, mt, first, last, idle in rows:
    name = pod if len(pod) <= W_POD else pod[:W_POD - 1] + "…"
    typ  = typ.replace("NVIDIA ", "").strip()
    typ  = typ if len(typ) <= W_TYPE else typ[:W_TYPE - 1] + "…"
    gpu_s  = c(f"{g:>3.0f}%",  tone(g))
    idle_s = c(f"{idle:>4.0f}%", (RED if idle >= 50 else YELLOW if idle >= 20 else GREY))
    print(f" {name:<{W_POD}}  {ubar(g, W_BAR)}  {gpu_s} {m:>3.0f}% {idle_s}  "
          f"{gpus:>4} {c(f'{n:>4}', DIM)}  {c(f'{typ:<{W_TYPE}}', GREY)}")

print(c("─" * WIDTH, GREY))
if rows:
    avg = sum(r[0] for r in rows) / len(rows)
    worst = rows[0]
    print(f" {dot(avg)} mean {c(f'{avg:.0f}%', tone(avg))}   "
          f"worst: {c(worst[2], BOLD)} "
          f"({c(f'{worst[0]:.0f}%', tone(worst[0]))} util, "
          f"{c(f'{worst[10]:.0f}% idle', RED if worst[10] >= 50 else GREY)})")
print(c(f" bar/GPU% = mean compute util · IDLE% = % of samples <{IDLE_THRESH}% util "
        f"(bursty-idle flag)", DIM))
PY
}

# ── idle: node-first list of continuous GPU-idle streaks (longest per pod) ─────
do_idle() {
  [[ -f "$LOG" ]] || { echo "No log yet at $LOG (run 'gpu-util-monitor sample' first)." >&2; exit 1; }
  MIN_IDLE="$MIN_IDLE" NS="$NAMESPACE" python3 - "$LOG" <<'PY'
import csv, os, sys
from collections import defaultdict

path    = sys.argv[1]
ns      = os.environ.get("NS", "")
min_min = int(os.environ.get("MIN_IDLE", "60"))   # only show streaks >= this many minutes
IDLE_THRESH = 5
COLOR = sys.stdout.isatty()
def c(s, code): return f"\033[{code}m{s}\033[0m" if COLOR else s
BOLD, DIM, RED, YELLOW, GREEN, CYAN, GREY = "1","2","38;5;203","38;5;220","38;5;42","38;5;44","38;5;244"

# pod -> chronological samples: (epoch, iso, gpu_util, node, num_gpus)
series = defaultdict(list)
with open(path, newline="") as f:
    for r in csv.DictReader(f):
        try:
            series[r["pod"]].append((int(r["epoch"]), r["iso"], int(r["avg_gpu_util"]),
                                     (r.get("node") or "-"), int(r["num_gpus"])))
        except (KeyError, ValueError):
            continue

def fmt_dur(sec):
    m = int(round(sec/60)); h, m = divmod(m, 60)
    return f"{h}h {m:02d}m" if h else f"{m}m"
def fmt_ts(iso):
    return iso.replace("T", " ")[:16]        # 2026-06-30T12:13:00 -> 2026-06-30 12:13

rows = []
for pod, s in series.items():
    s.sort()
    best = None                              # (dur_sec, start_idx, end_idx)
    run_start = None
    for j, smp in enumerate(s):
        if smp[2] < IDLE_THRESH:             # idle sample
            if run_start is None: run_start = j
            dur = s[j][0] - s[run_start][0]
            if best is None or dur > best[0]: best = (dur, run_start, j)
        else:
            run_start = None
    if best is None: continue
    dur, a, b = best
    if dur < min_min * 60: continue
    ongoing = (b == len(s) - 1)              # last sample is still idle
    node, gpus = s[b][3], s[b][4]
    rows.append((dur, pod, node, gpus, s[a][1], s[b][1], ongoing))

rows.sort(key=lambda x: -x[0])               # longest idle first

N_POD = 44
title = c("Idle GPU pods", BOLD) + c(f"  ns={ns}", CYAN) + c(f"  ·  streaks ≥ {min_min}m", DIM)
print(title)
if not rows:
    print(c(f"  none — no continuous idle streak ≥ {min_min}m in the log.", GREY))
else:
    wasted = 0.0
    for dur, pod, node, gpus, a_iso, b_iso, ongoing in rows:
        p = pod if len(pod) <= N_POD else pod[:N_POD-1] + "~"
        dcol = RED if dur >= 2*3600 else (YELLOW if dur >= 3600 else GREY)
        node_s = c(f"{node:<21}", GREY)          # pad plain, then colour (width kept)
        dur_s  = c(f"idle {fmt_dur(dur):<8}", dcol)
        flag   = c(" ●now", RED) if ongoing else ""
        print(f"  {node_s} {p:<{N_POD}}  {c(f'{gpus} GPU', BOLD)}  {dur_s}  "
              f"{c(f'({fmt_ts(a_iso)} → {fmt_ts(b_iso)})', DIM)}{flag}")
        wasted += (dur/3600.0) * gpus
    print(c("─" * 96, GREY))
    print(f"  {c(str(len(rows)),BOLD)} idle streaks  ·  "
          f"~{c(f'{wasted:.0f} GPU·h', BOLD)} wasted  ·  "
          f"{c('●now',RED)} = still idle at last sample")
PY
}

# ── cron install / uninstall ──────────────────────────────────────────────────
CRON_TAG="# gpu-util-monitor:${NAMESPACE}"
install_cron() {
  local line="0 */${EVERY_HOURS} * * * ${SELF} sample -n ${NAMESPACE} >> ${HOME}/gpu-util-logs/cron.log 2>&1  ${CRON_TAG}"
  if crontab -l 2>/dev/null | grep -qF "${CRON_TAG}"; then
    echo "Cron already installed for ns=${NAMESPACE}. Updating interval..." >&2
    ( crontab -l 2>/dev/null | grep -vF "${CRON_TAG}"; echo "${line}" ) | crontab -
  else
    ( crontab -l 2>/dev/null || true; echo "${line}" ) | crontab -
  fi
  mkdir -p "${HOME}/gpu-util-logs"
  echo "Installed: sample every ${EVERY_HOURS}h for ns=${NAMESPACE}." >&2
  echo "  log:    ${LOG}" >&2
  echo "  report: gpu-util-monitor report -n ${NAMESPACE}" >&2
}

uninstall_cron() {
  if crontab -l 2>/dev/null | grep -qF "${CRON_TAG}"; then
    crontab -l 2>/dev/null | grep -vF "${CRON_TAG}" | crontab -
    echo "Removed cron for ns=${NAMESPACE}. Log kept at ${LOG}." >&2
  else
    echo "No cron installed for ns=${NAMESPACE}." >&2
  fi
}

do_status() {
  echo "${BLD}namespace:${RST} ${NAMESPACE}"
  echo "${BLD}log:${RST}       ${LOG}"
  if [[ -f "$LOG" ]]; then
    local rows; rows=$(( $(wc -l < "$LOG") - 1 ))
    echo "${BLD}samples:${RST}   ${rows} rows"
  else
    echo "${BLD}samples:${RST}   (none yet)"
  fi
  if crontab -l 2>/dev/null | grep -qF "${CRON_TAG}"; then
    echo "${BLD}cron:${RST}      ${GRN}installed${RST}"
    crontab -l 2>/dev/null | grep -F "${CRON_TAG}" | sed 's/^/  /'
  else
    echo "${BLD}cron:${RST}      ${YEL}not installed${RST}"
  fi
}

case "$CMD" in
  sample)         do_sample;;
  report)         do_report;;
  idle)           do_idle;;
  install-cron)   install_cron;;
  uninstall-cron) uninstall_cron;;
  status)         do_status;;
  help|"")        usage;;
  *) echo "Unknown command: $CMD" >&2; usage;;
esac
