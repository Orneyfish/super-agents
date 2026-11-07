#!/usr/bin/env python3
"""Ticket board helper for specs/tickets/BOARD.md.

  board.py check [root]                    lint the board against the ticket folders
  board.py set <NNN|feature-dir> <status> [root]   status: draft|ready|building|done (RD.md, plus the board row for a ticket)
  board.py scan [root]                     one line per problem for the watchdog; no output = healthy
  board.py root                            print the main checkout of the repo containing the current directory

root defaults to the main checkout, even when run from inside a worktree."""
import datetime, fcntl, glob, hashlib, json, math, os, re, subprocess, sys, urllib.request

STATUSES = ("draft", "ready", "building", "done")
ROW = re.compile(r"^\|\s*(\d{3})\s*\|\s*(.*?)\s*\|\s*(\w+)\s*\|\s*(\w+)\s*\|\s*(.*?)\s*\|\s*$")


def main_checkout():
    try:
        common = os.path.realpath(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True, stderr=subprocess.DEVNULL).strip())
    except Exception:
        return os.getcwd()
    try:   # a submodule keeps its git dir in <superproject>/.git/modules and says where its files are in core.worktree
        wt = subprocess.check_output(["git", "--git-dir=" + common, "config", "--get", "core.worktree"], text=True, stderr=subprocess.DEVNULL).strip()
        return os.path.realpath(os.path.join(common, wt))
    except Exception:
        return os.path.dirname(common)


def board_path(root): return os.path.join(root, "specs", "tickets", "BOARD.md")


def rows(root):
    p = board_path(root)
    return [dict(id=m[1], title=m[2], status=m[3], mode=m[4], runs=m[5]) for m in map(ROW.match, open(p)) if m] if os.path.exists(p) else []


def ticket_dir(root, nnn):
    hits = glob.glob(os.path.join(root, "specs", "tickets", nnn + "-*"))
    return hits[0] if len(hits) == 1 else None


def rd_status(d):
    try:
        m = re.search(r"^\*\*Status:\*\*\s*(\w+)", open(os.path.join(d, "RD.md")).read(), re.M)
        return m[1] if m else None
    except OSError:
        return None


def deps(r):
    return re.findall(r"\d{3}", r["runs"].split(":")[0]) if r["runs"].startswith("waits for") else []


def cycles(rs):
    g = {r["id"]: deps(r) for r in rs}
    out, seen = [], set()
    def walk(n, path):
        if n in path: out.append(" -> ".join(path[path.index(n):] + [n])); return
        if n in seen or n not in g: return
        seen.add(n)
        for d in g[n]: walk(d, path + [n])
    for n in g: walk(n, [])
    return out


def check(root):
    rs, bad = rows(root), []
    if not os.path.exists(board_path(root)): bad.append("no specs/tickets/BOARD.md")
    ids = [r["id"] for r in rs]
    bad += [f"duplicate id {i}" for i in set(ids) if ids.count(i) > 1]
    for r in rs:
        d = ticket_dir(root, r["id"])
        if r["status"] not in STATUSES: bad.append(f"{r['id']}: status '{r['status']}' is not one of {STATUSES}")
        if r["mode"] not in ("solo", "team"): bad.append(f"{r['id']}: mode must be solo or team")
        if r["runs"] != "alongside" and not r["runs"].startswith("waits for"): bad.append(f"{r['id']}: Runs must be 'alongside' or 'waits for NNN: why'")
        if not d: bad.append(f"{r['id']}: no folder specs/tickets/{r['id']}-*"); continue
        if rd_status(d) != r["status"]: bad.append(f"{r['id']}: RD.md Status is '{rd_status(d)}', board says '{r['status']}'")
        bad += [f"{r['id']}: waits for {x}, which is not on the board" for x in deps(r) if x not in ids]
    for d in glob.glob(os.path.join(root, "specs", "tickets", "[0-9][0-9][0-9]-*")):
        if os.path.basename(d)[:3] not in ids: bad.append(f"{os.path.basename(d)} has no board row")
    bad += [f"dependency cycle {c}" for c in cycles(rs)]
    print("\n".join("FAIL: " + b for b in bad) if bad else f"OK: board ({len(rs)} tickets)")
    return 1 if bad else 0


def set_status(root, target, status):
    if status not in STATUSES: sys.exit(f"status must be one of {STATUSES}")
    nnn = target if re.fullmatch(r"\d{3}", target) else None
    d = ticket_dir(root, nnn) if nnn else target
    if not d or not os.path.isdir(d): sys.exit(f"no such ticket or directory: {target}")
    m = re.match(r"(\d{3})-", os.path.basename(os.path.normpath(d)))
    if m and os.path.basename(os.path.dirname(os.path.normpath(d))) == "tickets": nnn = m[1]   # a ticket dir keeps its board row in sync
    rd = os.path.join(d, "RD.md")
    txt = open(rd).read()
    line = f"**Status:** {status}"
    txt = re.sub(r"^\*\*Status:\*\*.*$", line, txt, count=1, flags=re.M) if re.search(r"^\*\*Status:\*\*", txt, re.M) else txt.replace("\n", "\n\n" + line + "\n", 1)
    open(rd, "w").write(txt)
    ev = os.path.join(d, "evals.md")
    if status == "ready" and os.path.exists(ev):   # fingerprint of what the user approved; check-evals --passed compares it
        open(os.path.join(d, ".evals.sha256"), "w", newline="\n").write(hashlib.sha256(open(ev, "rb").read()).hexdigest() + "\n")
    if nnn and os.path.exists(board_path(root)):
        with open(board_path(root), "r+") as f:      # lock: several agents flip rows at once
            fcntl.flock(f, fcntl.LOCK_EX)
            out = [re.sub(r"^(\|\s*%s\s*\|.*?\|\s*)\w+(\s*\|\s*\w+\s*\|)" % nnn, r"\g<1>%s\g<2>" % status, ln) for ln in f.read().split("\n")]
            f.seek(0); f.write("\n".join(out)); f.truncate()
    print(f"ok {target} -> {status}")


DEFAULTS = {"stale_min": "15", "wait_min": "45", "slow_min": "60", "ignore": "", "app_url": ""}


def conf(root):
    c = dict(DEFAULTS)
    try:
        for ln in open(os.path.join(root, ".super-agents", "watchdog.conf")):
            if "=" in ln and not ln.lstrip().startswith("#"): k, v = ln.split("=", 1); c[k.strip()] = v.strip()
    except OSError:
        pass
    return c


def limit(c, key):
    try:
        v = float(c[key])
        if math.isfinite(v): return v
    except ValueError: pass
    return float(DEFAULTS[key])   # a typo (or nan/inf, which never compare true) in watchdog.conf must not silence the watchdog


def minutes_since(iso):
    t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() / 60


def job_problems(r, js, c):
    out, started = [], []
    for j in js:   # one bad status file must not hide the others
        try:
            who = j.get("agent") or "worker"
            if j["phase"] == "blocked": out.append(f"PROBLEM {r['id']} {who} reports blocked: {j.get('note', '')}")
            # testing/reviewing: the worker is blocked on its own tester/reviewer and cannot heartbeat, so it gets wait_min
            elif j["phase"] != "done" and minutes_since(j["updated"]) > limit(c, "wait_min" if j["phase"] in ("testing", "reviewing") else "stale_min"):
                out.append(f"PROBLEM {r['id']} {who} silent for {minutes_since(j['updated']):.0f} min in phase '{j['phase']}'")
            started.append((j["phase"] != "done", minutes_since(j["started"])))
        except (KeyError, ValueError, TypeError, AttributeError) as e:
            out.append(f"PROBLEM {r['id']} status file unreadable: {e!r}")
    if any(active for active, _ in started) and max(m for _, m in started) > limit(c, "slow_min"):
        out.append(f"PROBLEM {r['id']} slow: building for {max(m for _, m in started):.0f} min")
    return out


def scan(root):
    c, rs, out = conf(root), rows(root), []
    skip = {x.strip() for x in c["ignore"].split(",") if x.strip()}
    files = glob.glob(os.path.join(root, ".claude", "worktrees", "*", ".job", "status*.json")) + glob.glob(os.path.join(root, ".job", "status-*.json"))
    jobs, bad = {}, []
    for f in files:
        try:
            j = json.load(open(f))
            jobs.setdefault(j.get("ticket"), []).append(j)
        except Exception as e: bad.append(f"PROBLEM {os.path.relpath(f, root)} unreadable: {e!r}")
    building = [r for r in rs if r["status"] == "building" and r["id"] not in skip]
    if building: out += bad   # a corrupt file names no ticket, so it only matters while something is building
    for r in building:
        js = jobs.get(r["id"], [])
        if not js: out.append(f"PROBLEM {r['id']} is 'building' but has no status file: the worker never started or died"); continue
        out += job_problems(r, js, c)
    out += [f"PROBLEM dependency cycle {x}" for x in cycles(rs)]
    if c["app_url"]:
        try: urllib.request.urlopen(c["app_url"], timeout=5)
        except Exception as e: out.append(f"PROBLEM main app not answering at {c['app_url']}: {e}")
    if out: print("\n".join(out))


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "root": print(main_checkout())
    elif cmd == "set" and len(a) >= 3: set_status(a[3] if len(a) > 3 else main_checkout(), a[1], a[2])
    elif cmd in ("check", "scan"):
        root = a[1] if len(a) > 1 else main_checkout()
        sys.exit(check(root)) if cmd == "check" else scan(root)
    else: sys.exit(__doc__)
