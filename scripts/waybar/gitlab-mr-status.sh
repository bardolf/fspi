#!/usr/bin/env bash
# Waybar module: GitLab MR status for ni_group
# Output: JSON with text, tooltip, class for waybar return-type=json
#
# Shows 4 metrics (assignee = ball in my court):
#   1.  MRs waiting for my review (I'm reviewer + assigned to me, haven't approved)
#   2.  My authored MRs that are fully approved but not merged
#   3.  My authored MRs with unresolved threads (assigned back to me)
#   4.  My authored MRs pending approval (not assigned to me = ball in reviewer's court)
#
# Uses Nerd Font icons

set -euo pipefail

GITLAB_USER="mi077548"
GITLAB_HOST="devops.cetin"
GROUP="it%2Fni_group"
TMPDIR_BASE="${XDG_RUNTIME_DIR:-/tmp}/waybar-gitlab-mrs"

# ============================================
# Helpers
# ============================================

cleanup() {
    rm -rf "$WORK_DIR"
}

output_error() {
    printf '{"text":" N/A","tooltip":"GitLab unreachable","class":"error"}\n'
    exit 0
}

# Create a unique working directory
mkdir -p "$TMPDIR_BASE"
export WORK_DIR
WORK_DIR=$(mktemp -d "$TMPDIR_BASE/run.XXXXXX")
trap cleanup EXIT

# ============================================
# Fetch data from GitLab API
# ============================================

# Fetch reviewer MRs and my authored MRs in parallel
glab api --hostname "$GITLAB_HOST" "groups/${GROUP}/merge_requests?state=opened&reviewer_username=${GITLAB_USER}&per_page=100" \
    > "$WORK_DIR/reviewer_mrs.json" 2>/dev/null &
pid_reviewer=$!

glab api --hostname "$GITLAB_HOST" "groups/${GROUP}/merge_requests?state=opened&author_username=${GITLAB_USER}&per_page=100" \
    > "$WORK_DIR/author_mrs.json" 2>/dev/null &
pid_author=$!

wait "$pid_reviewer" "$pid_author" || output_error

# ============================================
# Parse MR lists and fetch approvals
# ============================================

# Parse both lists, build approval pairs, fetch approvals in parallel - all in one python step
python3 -c "
import json

def parse_mrs(path):
    data = json.load(open(path))
    return [{'pid': m['project_id'], 'iid': m['iid'],
             'ref': m['references']['full'].replace('it/ni_group/', ''),
             'title': m['title'][:70],
             'url': m['web_url'],
             'assignees': [a['username'] for a in m.get('assignees', [])]}
            for m in data if not m.get('draft', False)]

reviewer = parse_mrs('$WORK_DIR/reviewer_mrs.json')
author = parse_mrs('$WORK_DIR/author_mrs.json')
json.dump(reviewer, open('$WORK_DIR/reviewer_parsed.json', 'w'))
json.dump(author, open('$WORK_DIR/author_parsed.json', 'w'))

# Collect unique (pid, iid) pairs
seen = set()
for m in reviewer + author:
    seen.add((m['pid'], m['iid']))
for pid, iid in sorted(seen):
    print(f'{pid} {iid}')
" > "$WORK_DIR/approval_pairs.txt" || output_error

# Fetch approvals in parallel using a read loop from file (not pipe)
pids=()
while read -r pid iid; do
    glab api --hostname "$GITLAB_HOST" "projects/${pid}/merge_requests/${iid}/approvals" \
        > "$WORK_DIR/approval_${pid}_${iid}.json" 2>/dev/null &
    pids+=($!)
done < "$WORK_DIR/approval_pairs.txt"

# Wait for all approval fetches
for p in "${pids[@]+"${pids[@]}"}"; do
    wait "$p" || true
done

# ============================================
# Fetch discussions for non-approved authored MRs
# ============================================

python3 -c "
import json, os

GITLAB_USER = '$GITLAB_USER'
author = json.load(open('$WORK_DIR/author_parsed.json'))
for m in author:
    pid, iid = m['pid'], m['iid']
    if GITLAB_USER not in m.get('assignees', []):
        continue
    path = '$WORK_DIR/approval_' + str(pid) + '_' + str(iid) + '.json'
    if os.path.exists(path):
        try:
            approval = json.load(open(path))
            if not approval.get('approved', False):
                print(f'{pid} {iid}')
        except (json.JSONDecodeError, KeyError):
            pass
" > "$WORK_DIR/need_discussions.txt" || output_error

pids=()
while read -r pid iid; do
    [[ -z "$pid" ]] && continue
    glab api --hostname "$GITLAB_HOST" "projects/${pid}/merge_requests/${iid}/discussions?per_page=100" \
        > "$WORK_DIR/discussions_${pid}_${iid}.json" 2>/dev/null &
    pids+=($!)
done < "$WORK_DIR/need_discussions.txt"

for p in "${pids[@]+"${pids[@]}"}"; do
    wait "$p" || true
done

# ============================================
# Compute all 3 metrics and build output
# ============================================

python3 << 'PYEOF'
import json, os

WORK_DIR = os.environ["WORK_DIR"]
GITLAB_USER = "mi077548"

reviewer_mrs = json.load(open(f"{WORK_DIR}/reviewer_parsed.json"))
author_mrs = json.load(open(f"{WORK_DIR}/author_parsed.json"))

def load_approval(pid, iid):
    path = f"{WORK_DIR}/approval_{pid}_{iid}.json"
    if os.path.exists(path):
        try:
            return json.load(open(path))
        except (json.JSONDecodeError, KeyError):
            pass
    return {}

def count_unresolved(pid, iid):
    path = f"{WORK_DIR}/discussions_{pid}_{iid}.json"
    if not os.path.exists(path):
        return 0
    try:
        discussions = json.load(open(path))
    except (json.JSONDecodeError, KeyError):
        return 0
    count = 0
    for d in discussions:
        for note in d.get("notes", []):
            if note.get("resolvable") and not note.get("resolved"):
                count += 1
                break  # count per discussion thread, not per note
    return count

# --- Metric 1: MRs waiting for my review (I haven't approved yet, and I'm assigned) ---
waiting_review = []
for m in reviewer_mrs:
    if GITLAB_USER not in m.get("assignees", []):
        continue
    approval = load_approval(m["pid"], m["iid"])
    approved_by = [u["user"]["username"] for u in approval.get("approved_by", [])]
    if GITLAB_USER not in approved_by:
        waiting_review.append(m)

# --- Metric 2: My MRs fully approved, not merged ---
my_approved = []
for m in author_mrs:
    approval = load_approval(m["pid"], m["iid"])
    if approval.get("approved", False):
        my_approved.append(m)

# --- Metric 3: My MRs not approved, with unresolved threads (assigned to me) ---
my_unresolved = []
# --- Metric 4: My MRs not yet approved (waiting for review, not assigned to me) ---
my_pending_approval = []
for m in author_mrs:
    approval = load_approval(m["pid"], m["iid"])
    if not approval.get("approved", False):
        is_assignee = GITLAB_USER in m.get("assignees", [])
        if is_assignee:
            unresolved = count_unresolved(m["pid"], m["iid"])
            if unresolved > 0:
                my_unresolved.append({**m, "unresolved": unresolved})
        else:
            my_pending_approval.append(m)

# --- Build output ---
n1 = len(waiting_review)
n2 = len(my_approved)
n3 = len(my_unresolved)
n4 = len(my_pending_approval)

text = f"\ue725 {n1} | \uf00c {n2} | \uf075 {n3} | \uf417 {n4}"

tooltip_parts = []

if waiting_review:
    lines = [f"\ue725 Waiting for my review ({n1}):"]
    for m in waiting_review:
        lines.append(f"  {m['ref']} - {m['title']}")
    tooltip_parts.append("\n".join(lines))
else:
    tooltip_parts.append("\ue725 Waiting for my review: none")

if my_approved:
    lines = [f"\uf00c My approved, unmerged ({n2}):"]
    for m in my_approved:
        lines.append(f"  {m['ref']} - {m['title']}")
    tooltip_parts.append("\n".join(lines))
else:
    tooltip_parts.append("\uf00c My approved, unmerged: none")

if my_unresolved:
    lines = [f"\uf075 My MRs with unresolved threads ({n3}):"]
    for m in my_unresolved:
        lines.append(f"  {m['ref']} ({m['unresolved']} unresolved) - {m['title']}")
    tooltip_parts.append("\n".join(lines))
else:
    tooltip_parts.append("\uf075 My MRs with unresolved threads: none")

if my_pending_approval:
    lines = [f"\uf417 My MRs pending approval ({n4}):"]
    for m in my_pending_approval:
        lines.append(f"  {m['ref']} - {m['title']}")
    tooltip_parts.append("\n".join(lines))
else:
    tooltip_parts.append("\uf417 My MRs pending approval: none")

tooltip = "\n\n".join(tooltip_parts)

css_class = "has-mrs" if (n1 + n2 + n3) > 0 else "no-mrs"

# --- Resolve click URL (priority: review > unresolved > approved > pending) ---
GITLAB_BASE = "https://devops.cetin"
GROUP_MRS = f"{GITLAB_BASE}/groups/it/ni_group/-/merge_requests"
FALLBACK_URL = f"{GROUP_MRS}?state=opened"

def pick_url(mrs, list_filter):
    if len(mrs) == 1:
        return mrs[0]["url"]
    return f"{GROUP_MRS}?state=opened&{list_filter}"

if n1 > 0:
    click_url = pick_url(waiting_review, f"reviewer_username={GITLAB_USER}")
elif n3 > 0:
    click_url = pick_url(my_unresolved, f"author_username={GITLAB_USER}&assignee_username={GITLAB_USER}")
elif n2 > 0:
    click_url = pick_url(my_approved, f"author_username={GITLAB_USER}")
elif n4 > 0:
    click_url = pick_url(my_pending_approval, f"author_username={GITLAB_USER}")
else:
    click_url = FALLBACK_URL

TMPDIR_BASE = os.environ.get("XDG_RUNTIME_DIR", "/tmp") + "/waybar-gitlab-mrs"
with open(f"{TMPDIR_BASE}/click_url", "w") as f:
    f.write(click_url)

output = json.dumps({"text": text, "tooltip": tooltip, "class": css_class}, ensure_ascii=False)
print(output)
PYEOF
