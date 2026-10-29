#!/usr/bin/env python3
"""Report ordering cycles in a systemd unit graph (PLAN F29).

Input: a dump of `systemctl show -p Id -p After -p Before -- <all loaded units>`
(blocks of `Key=value` lines separated by a blank line). Produce it with
check-boot-order.sh; this file is host-side only - the target has no python3.

Why this exists: a cyclic ordering graph does not fail a boot, systemd silently
deletes one job of the cycle to break it ("Job <unit>/start deleted to break
ordering cycle"), and which job it picks is not stable. That is how /data and
the user application once dropped out of the boot transaction while two
neighbouring units started fine (F29). "It booted" and even "it booted twice" is
therefore not evidence; this is.

Usage: check-boot-order.py <dump> [old]
  old  - replace the effective ordering of medicam-data.service with the pre-fix
         one (default dependencies => After=basic.target), i.e. the regression
         test for this checker: it must find the cycle again.

Exit status: 0 = no cycles, 1 = at least one cycle (or unreadable input).
"""
import re
import sys
from collections import defaultdict, deque

# Units of this board: reported separately, because a cycle anywhere else is
# usually systemd's own business, while a cycle here is ours.
SUSPECTS = [
    "medicam-data.service",
    "data.mount",
    "medicam-data-init.service",
    "medicam-hostname.service",
    "medicam-identity.service",
    "medicam.service",
    "local-fs.target",
]

OVERRIDE = {}
if len(sys.argv) > 2 and sys.argv[2] == "old":
    # medicam-data.service as shipped before F29: the explicit lines plus the
    # implicit default set of a service (Requires=sysinit.target,
    # After=sysinit.target basic.target, Conflicts/Before=shutdown.target).
    OVERRIDE["medicam-data.service"] = (
        ["system.slice", "systemd-journald.socket", "local-fs-pre.target",
         "sysinit.target", "basic.target"],
        ["data.mount", "local-fs.target", "shutdown.target"],
    )


def dec(name):
    """Undo systemctl's quoting/escaping: "\\\\x2d" -> "-", "\\\\x40" -> "@"."""
    name = name.strip('"')
    while "\\\\x" in name:                     # collapse doubled backslashes
        name = name.replace("\\\\x", "\\x")
    return re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), name)


def parse(path):
    units, after, before = set(), {}, {}
    block = {}

    def flush():
        if block.get("Id"):
            n = dec(block["Id"])
            units.add(n)
            after[n] = [dec(t) for t in block.get("After", "").split()]
            before[n] = [dec(t) for t in block.get("Before", "").split()]

    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line.strip():
            flush()
            block = {}
        elif "=" in line:
            k, v = line.split("=", 1)
            block[k] = v
    flush()
    for name, (a, b) in OVERRIDE.items():
        after[name], before[name] = a, b
    return units, after, before


def build(units, after, before):
    """Digraph of "X must be started before Y"."""
    g = defaultdict(set)
    skipped = set()
    for u in units:
        g[u]
        for x in after.get(u, ()):           # u is After x  ->  x before u
            if x in units:
                g[x].add(u)
            else:
                skipped.add(x)
        for y in before.get(u, ()):          # u is Before y ->  u before y
            if y in units:
                g[u].add(y)
            else:
                skipped.add(y)
    return g, skipped


def cycles(g):
    """All elementary cycles, deduplicated (DFS from each node in index order)."""
    order = {n: i for i, n in enumerate(sorted(g))}
    found, seen = [], set()
    for start in sorted(g):
        stack = [(start, iter(sorted(g.get(start, ()), key=lambda n: order[n])))]
        path = [start]
        onpath = {start}
        while stack:
            node, it = stack[-1]
            for nxt in it:
                if nxt == start:
                    cyc = tuple(path)
                    key = min(tuple(cyc[i:] + cyc[:i]) for i in range(len(cyc)))
                    if key not in seen:
                        seen.add(key)
                        found.append(key)
                    continue
                if nxt in onpath or order[nxt] < order[start]:
                    continue
                stack.append((nxt, iter(sorted(g.get(nxt, ()),
                                              key=lambda n: order[n]))))
                path.append(nxt)
                onpath.add(nxt)
                break
            else:
                stack.pop()
                onpath.discard(path.pop())
        if len(found) > 500:
            break
    return found


def shortest_cycle(g, node):
    """BFS for the shortest cycle node -> ... -> node."""
    prev = {node: None}
    q = deque([node])
    while q:
        cur = q.popleft()
        for nxt in sorted(g.get(cur, ())):
            if nxt == node:
                path = [cur]
                while prev[path[-1]] is not None:
                    path.append(prev[path[-1]])
                path.reverse()
                return path + [node]
            if nxt not in prev:
                prev[nxt] = cur
                q.append(nxt)
    return None


def main():
    try:
        units, after, before = parse(sys.argv[1])
    except (OSError, IndexError) as exc:
        print(f"cannot read the unit dump: {exc}", file=sys.stderr)
        return 2
    g, skipped = build(units, after, before)
    print(f"loaded units: {len(units)}, ordering edges: "
          f"{sum(len(v) for v in g.values())}")
    print(f"edges dropped (name not a loaded unit): {len(skipped)}"
          + ("" if not skipped else " -> " + ", ".join(sorted(skipped))))
    if len(units) < 50:
        print("WARNING: suspiciously small graph - is this a full "
              "'systemctl list-units --all' dump?", file=sys.stderr)
    cyc = cycles(g)
    ours = [c for c in cyc if any(n in SUSPECTS for n in c)]
    print(f"ordering cycles: {len(cyc)} (touching MediCam units: {len(ours)})")
    for c in cyc[:8]:
        print("  cycle:", " -> ".join(c + (c[0],)))
    print("shortest cycle through:")
    for s in SUSPECTS:
        if s not in units:
            print(f"  {s}: (not loaded)")
            continue
        p = shortest_cycle(g, s)
        print(f"  {s}: {'none' if p is None else ' -> '.join(p)}")
    return 1 if cyc else 0


if __name__ == "__main__":
    sys.exit(main())
