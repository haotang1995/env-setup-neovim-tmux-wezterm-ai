# kubectl shortcuts for the bonete51 namespace.
# install.sh symlinks this to ~/.k_shortcuts.sh; zshrc and bashrc source it.
# Must stay valid in both shells: no 0-based array indexing (zsh arrays start
# at 1), no `local` inside loops (zsh prints already-set locals), and no
# `echo` of JSON (zsh expands its escapes; use printf '%s\n').
#
# Override defaults inline: `KNS=otherns KUSER=somebody ksh`

KNS="${KNS:-bonete51}"
KUSER="${KUSER:-$(whoami | cut -d'@' -f1)}"

# --- Helpers ---------------------------------------------------------------

# Resolve a pod name:
#   - no arg / "-"        -> newest pod matching $KUSER-*
#   - exact pod name      -> returned as-is
#   - substring / pattern -> newest pod whose name contains it
_k_pod() {
    local arg="${1:-}"
    local pat
    if [[ -z "$arg" || "$arg" == "-" ]]; then
        pat="${KUSER}-"
    elif kubectl get pod "$arg" -n "$KNS" >/dev/null 2>&1; then
        echo "$arg"; return 0
    else
        pat="$arg"
    fi
    local pod
    pod=$(kubectl get pods -n "$KNS" --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
          | grep -- "$pat" | tail -n1)
    if [[ -z "$pod" ]]; then
        echo "no pod matching '$pat' in ns $KNS" >&2
        return 1
    fi
    echo "$pod"
}

# --- Listing ---------------------------------------------------------------

# kpods            -> all pods in namespace
# kpods <pattern>  -> only pods matching pattern
# kpods me         -> only $KUSER-* pods
kpods() {
    if [[ "${1:-}" == "me" ]]; then
        kubectl get pods -n "$KNS" -o wide | awk -v u="$KUSER" 'NR==1 || $1 ~ "^"u'
    elif [[ -n "${1:-}" ]]; then
        kubectl get pods -n "$KNS" -o wide | awk -v p="$1" 'NR==1 || $1 ~ p'
    else
        kubectl get pods -n "$KNS" -o wide
    fi
}

# --- Per-pod commands ------------------------------------------------------

kdesc() {
    local pod; pod=$(_k_pod "${1:-}") || return 1
    kubectl describe pod "$pod" -n "$KNS"
}

# klogs [pod] [-p|--previous]   -p tails the previous container instance
klogs() {
    local prev="" pod_arg="" a
    for a in "$@"; do
        case "$a" in
            -p|--previous) prev="--previous" ;;
            *) [[ -z "$pod_arg" ]] && pod_arg="$a" ;;
        esac
    done
    local pod; pod=$(_k_pod "$pod_arg") || return 1
    kubectl logs -f $prev "$pod" -n "$KNS"
}

# ksh [pod]                      shell into pod
ksh() {
    local pod; pod=$(_k_pod "${1:-}") || return 1
    kubectl exec -it "$pod" -n "$KNS" -- bash
}

# krun [pod] -- cmd args...      one-shot command, no TTY
krun() {
    local pod_arg=""
    if [[ "${1:-}" != "--" ]]; then
        pod_arg="$1"; shift
    fi
    [[ "${1:-}" == "--" ]] && shift
    local pod; pod=$(_k_pod "$pod_arg") || return 1
    kubectl exec "$pod" -n "$KNS" -- "$@"
}

# kev [pod]                      recent events for a pod
kev() {
    local pod; pod=$(_k_pod "${1:-}") || return 1
    kubectl get events -n "$KNS" --field-selector involvedObject.name="$pod" \
        --sort-by=.lastTimestamp
}

# kpf [pod] <localPort:remotePort>...   a leading port spec (N, N:M, :M)
#                                       means "no pod given": forward from
#                                       your newest pod. `-` also means that.
kpf() {
    local pod_arg=""
    case "${1:-}" in
        ''|*:*) ;;                          # no args, or a [local]:remote spec
        *[!0-9]*) pod_arg="$1"; shift ;;    # has a non-digit: pod name or `-`
        *) ;;                               # wholly numeric: a local port
    esac
    local pod; pod=$(_k_pod "$pod_arg") || return 1
    kubectl port-forward -n "$KNS" "$pod" "$@"
}

# --- Namespace / cluster GPU view -----------------------------------------

# kgpu       -> per-pod GPU requests in namespace (Running/Pending only), with
#               the Volcano queue and priority class of each pod. Pods in the
#               "$KNS-opp" queue run on borrowed GPUs and can be preempted.
kgpu() {
    local pods_json
    pods_json=$(kubectl get pods -n "$KNS" -o json) \
        || { echo "kgpu: could not list pods in $KNS" >&2; return 1; }
    printf '%s\n' "$pods_json" | python3 -c '
import json, sys
opp = sys.argv[1] + "-opp"
rows, by_q = [], {}
for p in json.load(sys.stdin)["items"]:
    ph = p["status"].get("phase", "")
    if ph not in ("Running", "Pending"): continue
    g = sum(int(c.get("resources", {}).get("requests", {}).get("nvidia.com/gpu", 0))
            for c in p["spec"].get("containers", []))
    if g == 0: continue
    q = p["metadata"].get("annotations", {}).get("volcano.sh/queue-name", "-")
    rows.append((p["metadata"]["name"], g, ph, q, p["spec"].get("priorityClassName", "-")))
    run, pend = by_q.get(q, (0, 0))
    by_q[q] = (run + g, pend) if ph == "Running" else (run, pend + g)
rows.sort(key=lambda r: (r[3] == opp, r[3], -r[1], r[0]))
fmt = "{:%d} {:>5}  {:8} {:14} {}" % max([len(r[0]) for r in rows] + [3])
print(fmt.format("POD", "GPUS", "PHASE", "QUEUE", "PRIO"))
for r in rows: print(fmt.format(*r))
print()
qfmt = "{:20} {:>8} {:>8}  {}"
print(qfmt.format("GPUS BY QUEUE", "RUNNING", "PENDING", "").rstrip())
for q in sorted(by_q, key=lambda q: (q == opp, q)):
    print(qfmt.format(q, *by_q[q], "<- borrowed, preemptable" if q == opp else "").rstrip())
print("Total GPUs requested (Running+Pending):", sum(a + b for a, b in by_q.values()))
' "$KNS"
}

# knodes     -> per-node GPU capacity, with $KNS-namespace usage.
#               NS_USED = GPUs taken by pods in $KNS on that node; OPP = how
#               many of those are borrowed through the "$KNS-opp" queue.
#               Cluster-wide free is not shown because listing pods
#               cluster-wide requires permissions a regular user doesn't have.
knodes() {
    local pods_json nodes ns_used node n o name cap
    pods_json=$(kubectl get pods -n "$KNS" -o json) \
        || { echo "knodes: could not list pods in $KNS" >&2; return 1; }
    nodes=$(kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}') \
        || { echo "knodes: could not list nodes" >&2; return 1; }
    # printf, not echo: zsh echo expands the \n / \" escapes inside the JSON.
    ns_used=$(printf '%s\n' "$pods_json" | python3 -c '
import json, sys
opp = sys.argv[1] + "-opp"
out = {}
for p in json.load(sys.stdin)["items"]:
    if p["status"].get("phase") not in ("Running", "Pending"): continue
    n = p["spec"].get("nodeName")
    if not n: continue
    g = sum(int(c.get("resources", {}).get("requests", {}).get("nvidia.com/gpu", 0))
            for c in p["spec"].get("containers", []))
    if not g: continue
    is_opp = p["metadata"].get("annotations", {}).get("volcano.sh/queue-name") == opp
    used, borrowed = out.get(n, (0, 0))
    out[n] = (used + g, borrowed + (g if is_opp else 0))
for k, (u, b) in out.items(): print(k, u, b)
' "$KNS") || return 1
    declare -A used_map=() opp_map=()
    while read -r node n o; do
        [[ -n "$node" ]] && { used_map[$node]=$n; opp_map[$node]=$o; }
    done <<< "$ns_used"

    printf "%-40s %4s %8s %4s\n" "NODE" "CAP" "NS_USED" "OPP"
    while read -r name cap; do
        [[ -z "$name" || -z "$cap" || "$cap" == "0" ]] && continue
        printf "%-40s %4d %8d %4d\n" "$name" "$cap" "${used_map[$name]:-0}" "${opp_map[$name]:-0}"
    done <<< "$nodes"
}

# kgpumon [sample|report|idle|install-cron|uninstall-cron|status] [args]
#   Long-horizon GPU-utilization tracking (see scripts/gpu-util-monitor.sh).
#   Passes the current $KNS as the namespace. Typical use:
#     kgpumon install-cron          # sample every 2h into a per-ns CSV log
#     kgpumon report                # rank pods worst->best by avg GPU util
#     kgpumon idle                  # node-first list of continuous idle streaks
kgpumon() {
    local sub="${1:-status}"; shift || true
    gpu-util-monitor "$sub" -n "$KNS" "$@"
}

# --- Volcano queues / opportunistic capacity -------------------------------
#
# Each namespace has two Volcano queues. "$KNS" is its own GPU allocation
# (capped). "$KNS-opp" borrows idle GPUs from other namespaces, uncapped,
# at priority low; the owner can preempt them at any time. A regular user
# cannot list other queues, so there is no way to see how much is free to
# borrow: submit with kopp and watch whether the job starts.

# kq         -> both queues: GPUs used vs cap, jobs running, and jobs waiting
#               (with the GPUs they want, how long, and why)
kq() {
    # Every query must succeed: a failed podgroup list would otherwise read as
    # "0 running, 0 waiting". GCR gave every namespace an opp queue; a missing
    # one comes back Forbidden (not NotFound), so it is an error too.
    local qs pgs
    qs=$(kubectl get queue "$KNS" "${KNS}-opp" -o json) \
        || { echo "kq: could not read queues $KNS / ${KNS}-opp" >&2; return 1; }
    pgs=$(kubectl get podgroup -n "$KNS" -o json) \
        || { echo "kq: could not list podgroups in $KNS" >&2; return 1; }
    printf '%s\n' "$qs" "$pgs" | python3 -c '
import datetime, json, sys
ns = sys.argv[1]; opp = ns + "-opp"
buf, i, dec, items = sys.stdin.read(), 0, json.JSONDecoder(), []
while True:
    while i < len(buf) and buf[i].isspace(): i += 1
    if i >= len(buf): break
    doc, i = dec.raw_decode(buf, i)
    items += doc.get("items", []) if doc.get("kind") == "List" else [doc]
queues = {o["metadata"]["name"]: o for o in items if o.get("kind") == "Queue"}
pgs = [o for o in items if o.get("kind") == "PodGroup"]
if not queues: sys.exit("kq: could not read queue " + ns)
def age(ts):
    t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    s = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return f"{d}d{h}h" if d else f"{h}h{m}m" if h else f"{m}m"
def gpus(pg):
    r = pg["spec"].get("minResources", {})
    return int(r.get("nvidia.com/gpu", r.get("requests.nvidia.com/gpu", 0)))
waiting = [pg for pg in pgs if pg.get("status", {}).get("phase") in ("Pending", "Inqueue")]
active = [pg for pg in pgs if pg.get("status", {}).get("phase") in ("Running", "Pending", "Inqueue")]
fmt = "{:16} {:>8} {:>8} {:>8}  {}"
print(fmt.format("QUEUE", "GPU_USED", "GPU_CAP", "RUNNING", "WAITING"))
for q in sorted(set(queues) | {pg["spec"].get("queue") for pg in active if pg["spec"].get("queue")},
                key=lambda q: (q != ns, q != opp, q)):
    o = queues.get(q, {})
    used = o.get("status", {}).get("allocated", {}).get("nvidia.com/gpu", "?" if not o else "0")
    cap = o.get("spec", {}).get("capability", {}).get("nvidia.com/gpu", "-")
    run = sum(1 for pg in pgs if pg["spec"].get("queue") == q and pg.get("status", {}).get("phase") == "Running")
    w = [pg for pg in waiting if pg["spec"].get("queue") == q]
    state = o.get("status", {}).get("state", "")
    note = "" if state in ("", "Open") else f"  [{state}]"
    print(fmt.format(q, used, cap, run, f"{len(w)} ({sum(map(gpus, w))} GPU){note}" if w else "0" + note))
if waiting:
    print("\nWAITING JOBS (oldest first)")
    for pg in sorted(waiting, key=lambda pg: pg["metadata"]["creationTimestamp"]):
        own = pg["metadata"].get("ownerReferences") or [{}]
        conds = pg.get("status", {}).get("conditions") or [{}]
        print("  {:55} {:14} {:>3} GPU  {:>6}  {}".format(
            own[0].get("name", pg["metadata"]["name"]), pg["spec"].get("queue", "-"),
            gpus(pg), age(pg["metadata"]["creationTimestamp"]), conds[-1].get("reason", "")))
' "$KNS"
}

# kvj [me|pattern]  -> Volcano jobs in namespace (the vcjob twin of `kh`):
#                      queue, priority, state, GPUs, restarts, age.
#                      PRIO "-" = unset at job level; pods then get the
#                      cluster default (medium on Bonete). RESTARTS is
#                      .status.retryCount: total job retries for any cause
#                      (eviction, pod failure, ...). It is not an eviction
#                      count; check the cause with `kubectl describe vcjob`
#                      while its events last (~1h).
kvj() {
    local jobs_json
    jobs_json=$(kubectl get vcjob -n "$KNS" -o json) \
        || { echo "kvj: could not list vcjobs in $KNS" >&2; return 1; }
    printf '%s\n' "$jobs_json" | python3 -c '
import datetime, json, re, sys
arg, user = sys.argv[1], sys.argv[2]
def age(ts):
    t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    s = int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds())
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return f"{d}d{h}h" if d else f"{h}h{m}m" if h else f"{m}m"
def res(c):
    # Per-key fallback: a missing GPU request defaults to the GPU limit even
    # when requests holds other keys (vcjob templates are not defaulted).
    r = c.get("resources", {})
    return int((r.get("requests") or {}).get("nvidia.com/gpu")
               or (r.get("limits") or {}).get("nvidia.com/gpu") or 0)
rows = []
for j in json.load(sys.stdin)["items"]:
    md, s, st = j["metadata"], j["spec"], j.get("status", {})
    n = md["name"]
    if arg == "me" and not n.startswith(user + "-"): continue
    if arg not in ("", "me") and not re.search(arg, n): continue
    tasks = s.get("tasks", [])
    prio = s.get("priorityClassName") or next((t["template"]["spec"]["priorityClassName"] for t in tasks
            if t.get("template", {}).get("spec", {}).get("priorityClassName")), "-")
    g = sum(t.get("replicas", 1) * sum(map(res, t.get("template", {}).get("spec", {}).get("containers", [])))
            for t in tasks)
    rows.append((md["creationTimestamp"], n, s.get("queue", "-"), prio,
                 st.get("state", {}).get("phase", "-"), g, st.get("retryCount", 0)))
if not rows: sys.exit("no vcjobs" + ("" if not arg else " matching " + repr(arg)))
w = max(len(r[1]) for r in rows)
fmt = "{:%d}  {:14} {:7} {:11} {:>5} {:>8} {:>6}" % w
print(fmt.format("NAME", "QUEUE", "PRIO", "STATE", "GPUS", "RESTARTS", "AGE"))
for r in sorted(rows):
    print(fmt.format(*r[1:], age(r[0])))
' "${1:-}" "$KUSER"
}

# kvjrm <job>       -> delete a Volcano job (and its pods; frees the GPUs)
kvjrm() {
    [[ -z "${1:-}" ]] && { echo "usage: kvjrm <job>" >&2; return 1; }
    kubectl delete vcjob "$1" -n "$KNS"
}

# kopp <job.yaml> [--dry-run]
#   Submit a Volcano Job to the opportunistic queue "$KNS-opp". The spec is
#   rewritten in flight; the file is not touched:
#     spec.queue -> $KNS-opp, schedulerName -> volcano,
#     priorityClassName -> low on the job and on every task,
#     annotations volcano.sh/preemptable=true and volcano.sh/cooldown-time
#     (60s unless the file already sets one).
#   Validates with a server-side dry run, then `kubectl create`s (safe for
#   generateName). --dry-run prints the validated job instead of creating it.
#   Under a restart policy an eviction reruns the job (or task) from the
#   start, so it must resume from the PVC. kopp
#   warns when any task would not restart on eviction: the policy that
#   applies (task-level first, then job-level; event PodEvicted or "*") is
#   missing or its action is not RestartJob/Task/Pod/Partition. It also
#   warns on a maxRetry of 1-2 (each restart uses one retry; past maxRetry
#   Volcano marks the job Failed).
#   maxRetry 0 is not "never retry" here: admission rewrites it to 3.
kopp() {
    local file="" dry="" a json
    for a in "$@"; do
        case "$a" in
            --dry-run) dry=1 ;;
            -*) echo "kopp: unknown option '$a'" >&2; return 1 ;;
            *) file="$a" ;;
        esac
    done
    [[ -n "$file" && -f "$file" ]] || { echo "usage: kopp <job.yaml> [--dry-run]" >&2; return 1; }
    json=$(kubectl create --dry-run=client -o json -f "$file") || return 1
    json=$(python3 -c '
import json, sys
opp = sys.argv[1] + "-opp"
doc = json.load(sys.stdin)
items = doc.get("items", []) if doc.get("kind") == "List" else [doc]
jobs = [o for o in items if o.get("kind") == "Job" and o.get("apiVersion", "").startswith("batch.volcano.sh/")]
if not jobs: sys.exit("kopp: no Volcano Job (apiVersion batch.volcano.sh/...) in the file")
def res(c):
    # Per-key fallback: a missing GPU request defaults to the GPU limit even
    # when requests holds other keys (vcjob templates are not defaulted).
    r = c.get("resources", {})
    return int((r.get("requests") or {}).get("nvidia.com/gpu")
               or (r.get("limits") or {}).get("nvidia.com/gpu") or 0)
RESTARTS = ("RestartJob", "RestartTask", "RestartPod", "RestartPartition")
def evict_action(pols):
    # First policy whose event (or events list) is PodEvicted or "*".
    for p in pols:
        if {"PodEvicted", "*"} & set([p.get("event")] + (p.get("events") or [])):
            return p.get("action")
    return None
for j in jobs:
    md, s = j.setdefault("metadata", {}), j.setdefault("spec", {})
    ann = md.setdefault("annotations", {})
    ann["volcano.sh/preemptable"] = "true"
    cooldown = ann.setdefault("volcano.sh/cooldown-time", "60s")
    s["queue"], s["schedulerName"], s["priorityClassName"] = opp, "volcano", "low"
    tasks = s.get("tasks", [])
    for t in tasks:
        t.setdefault("template", {}).setdefault("spec", {})["priorityClassName"] = "low"
    name = md.get("name") or md.get("generateName", "?") + "*"
    g = sum(t.get("replicas", 1) * sum(map(res, t["template"]["spec"].get("containers", []))) for t in tasks)
    print(f"kopp: {name} -> queue {opp}, priority low, preemptable, cooldown {cooldown}, {g} GPU",
          file=sys.stderr)
    # Task-level policies override job-level ones, so resolve per task.
    job_act, bad = evict_action(s.get("policies") or []), {}
    for t in tasks:
        act = evict_action(t.get("policies") or []) or job_act
        if act not in RESTARTS:
            bad.setdefault(act, []).append(t.get("name", "?"))
    for act, names in bad.items():
        who = "" if len(names) == len(tasks) else " (task " + ", ".join(names) + ")"
        if act is None:
            print(f"kopp: warning: no PodEvicted policy{who}; add {{event: PodEvicted, action: RestartJob}}"
                  " so an eviction restarts the job", file=sys.stderr)
        else:
            print(f"kopp: warning: PodEvicted -> {act}{who}: a preemption will not restart the job"
                  " (use RestartJob)", file=sys.stderr)
    mr = s.get("maxRetry") or 3  # Bonete admission rewrites 0 to the default, 3
    if mr < 3:
        print(f"kopp: warning: maxRetry={mr}: Volcano marks the job Failed after {mr} restart(s),"
              " and each eviction uses one", file=sys.stderr)
json.dump(doc, sys.stdout)
' "$KNS" <<<"$json") || return 1
    if [[ -n "$dry" ]]; then
        kubectl create --dry-run=server -n "$KNS" -o yaml -f - <<<"$json"
    else
        kubectl create --dry-run=server -n "$KNS" -f - <<<"$json" >/dev/null \
            && kubectl create -n "$KNS" -f - <<<"$json"
    fi
}

# --- PVC disk usage (gcr-duc) ----------------------------------------------

# kduc [viewer|status|index|help|version] [args]
#   Wraps the `kubectl duc` plugin (GCR PVC Storage Viewer), defaulting the
#   namespace to $KNS. A bare `kduc` opens the interactive disk-usage viewer.
#   Target a specific PVC with -p/--pvc NAME; override the namespace with
#   -n/--namespace (then $KNS is not injected). `help`/`version` take no ns.
#     kduc                       # interactive viewer for $KNS
#     kduc -p vast-pvc-bonete51  # viewer for a specific PVC
#     kduc -l                    # show the UI navigation legend
#     kduc status                # indexer status (last / running)
#     kduc index                 # launch a one-off index job
kduc() {
    local sub="viewer"
    case "${1:-}" in
        viewer|status|index|help|version) sub="$1"; shift ;;
    esac
    # help/version are namespace-agnostic; pass through untouched.
    if [[ "$sub" == "help" || "$sub" == "version" ]]; then
        kubectl duc "$sub" "$@"
        return
    fi
    # Inject -n $KNS only when the caller didn't supply a namespace.
    local a
    for a in "$@"; do
        case "$a" in -n|--namespace) kubectl duc "$sub" "$@"; return ;; esac
    done
    kubectl duc "$sub" -n "$KNS" "$@"
}

# kducs [args]   -> DUC indexer status in $KNS
kducs() { kduc status "$@"; }

# kduci [args]   -> launch a one-off DUC index job in $KNS
kduci() { kduc index "$@"; }

# kduc-install [DIR]
#   Install the GCR `duc` krew plugin from locally-downloaded artifacts.
#   The plugin isn't in the public krew index — download both files from the
#   GCR "PVC Storage Viewer" Azure DevOps wiki page first:
#       kubectl-duc_linux.tar.gz
#       kubectl-duc-krew-manifest-linux.yaml
#   Searches DIR, else $KDUC_ARTIFACT_DIR, ./kubectl-dev, ~/kubectl-dev,
#   ~/Downloads for the pair. Requires kubectl + krew.
kduc-install() {
    local arch="kubectl-duc_linux.tar.gz"
    local manifest="kubectl-duc-krew-manifest-linux.yaml"
    local dir="${1:-${KDUC_ARTIFACT_DIR:-}}" d
    if [[ -n "$dir" ]]; then
        [[ -f "$dir/$arch" && -f "$dir/$manifest" ]] || {
            echo "kduc-install: $arch + $manifest not found in '$dir'" >&2; return 1; }
    else
        for d in "$PWD/kubectl-dev" "$HOME/kubectl-dev" "$HOME/Downloads"; do
            [[ -f "$d/$arch" && -f "$d/$manifest" ]] && { dir="$d"; break; }
        done
        [[ -n "$dir" ]] || {
            echo "kduc-install: could not find $arch + $manifest." >&2
            echo "  Download both from the GCR 'PVC Storage Viewer' ADO wiki page," >&2
            echo "  drop them in ./kubectl-dev (or ~/Downloads), then re-run." >&2
            return 1; }
    fi
    command -v kubectl >/dev/null 2>&1 || { echo "kduc-install: kubectl not found" >&2; return 1; }
    kubectl krew version >/dev/null 2>&1 || {
        echo "kduc-install: krew not installed — see https://krew.sigs.k8s.io/docs/user-guide/setup/install/" >&2
        return 1; }
    if kubectl krew list 2>/dev/null | sed 's#.*/##' | grep -qx duc; then
        echo "duc plugin already installed: $(kubectl duc version 2>/dev/null)"
        echo "To reinstall from '$dir': kubectl krew uninstall duc && kduc-install '$dir'"
        return 0
    fi
    echo "Installing duc plugin from '$dir' ..."
    kubectl krew install --manifest="$dir/$manifest" --archive="$dir/$arch" \
        && kubectl duc version
}

# --- Helm shortcuts --------------------------------------------------------

# kh                    -> helm releases in namespace
# kh me                 -> only $KUSER-* releases
kh() {
    if [[ "${1:-}" == "me" ]]; then
        helm list -n "$KNS" | awk -v u="$KUSER" 'NR==1 || $1 ~ "^"u'
    else
        helm list -n "$KNS"
    fi
}

# khrm <release>        -> uninstall helm release in namespace
khrm() {
    [[ -z "${1:-}" ]] && { echo "usage: khrm <release>"; return 1; }
    helm uninstall "$1" -n "$KNS"
}

# khclean               -> uninstall ALL $KUSER-* helm releases (prompts)
khclean() {
    local rels
    rels=$(helm list -n "$KNS" -q | grep "^${KUSER}-" || true)
    [[ -z "$rels" ]] && { echo "no ${KUSER}-* releases"; return 0; }
    echo "Will uninstall:"; echo "$rels" | sed 's/^/  /'
    read -r -p "Proceed? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || return 1
    echo "$rels" | xargs -r -n1 helm uninstall -n "$KNS"
}
