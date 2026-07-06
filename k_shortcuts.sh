# kubectl shortcuts for the bonete51 namespace.
# Source from your shell rc:  source /path/to/keystone/infra/k_shortcuts.sh
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
    local prev=""
    local args=()
    for a in "$@"; do
        case "$a" in
            -p|--previous) prev="--previous" ;;
            *) args+=("$a") ;;
        esac
    done
    local pod; pod=$(_k_pod "${args[0]:-}") || return 1
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

# kpf [pod] <localPort:remotePort>
kpf() {
    local pod; pod=$(_k_pod "${1:-}") || return 1
    shift
    kubectl port-forward -n "$KNS" "$pod" "$@"
}

# --- Namespace / cluster GPU view -----------------------------------------

# kgpu       -> per-pod GPU requests in namespace (Running/Pending only)
kgpu() {
    kubectl get pods -n "$KNS" -o json | python3 -c '
import json, sys
rows = []
total = 0
for p in json.load(sys.stdin)["items"]:
    ph = p["status"].get("phase","")
    if ph not in ("Running","Pending"): continue
    g = sum(int(c.get("resources",{}).get("requests",{}).get("nvidia.com/gpu",0))
            for c in p["spec"].get("containers",[]))
    if g == 0: continue
    rows.append((p["metadata"]["name"], g, ph))
    total += g
rows.sort(key=lambda r: -r[1])
print("{:55} {:>5}  {}".format("POD","GPUS","PHASE"))
for n,g,ph in rows: print("{:55} {:>5}  {}".format(n,g,ph))
print("\nTotal allocated GPUs (Running+Pending):", total)
'
}

# knodes     -> per-node GPU capacity, with $KNS-namespace usage.
#               NS_USED = GPUs taken by pods in $KNS on that node. Cluster-wide
#               free is not shown because listing pods cluster-wide requires
#               permissions a regular user doesn't have.
knodes() {
    local pods_json
    pods_json=$(kubectl get pods -n "$KNS" -o json 2>/dev/null) || return 1
    local ns_used
    ns_used=$(echo "$pods_json" | python3 -c '
import json, sys
out = {}
for p in json.load(sys.stdin)["items"]:
    if p["status"].get("phase") not in ("Running","Pending"): continue
    n = p["spec"].get("nodeName")
    if not n: continue
    for c in p["spec"].get("containers", []):
        g = c.get("resources",{}).get("requests",{}).get("nvidia.com/gpu")
        if g: out[n] = out.get(n,0) + int(g)
for k,v in out.items(): print(f"{k} {v}")
')
    declare -A used_map=()
    while read -r node n; do [[ -n "$node" ]] && used_map[$node]=$n; done <<< "$ns_used"

    printf "%-40s %4s %8s\n" "NODE" "CAP" "NS_USED"
    while read -r line; do
        local name cap
        name=$(echo "$line" | awk '{print $1}')
        cap=$( echo "$line" | awk '{print $2}')
        [[ -z "$name" || -z "$cap" || "$cap" == "0" ]] && continue
        printf "%-40s %4d %8d\n" "$name" "$cap" "${used_map[$name]:-0}"
    done < <(kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}')
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
