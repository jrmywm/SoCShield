"""Audit real VCD handshakes and render SVG excerpts. Standard library only."""
from pathlib import Path
from html import escape
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "figures"
OUT.mkdir(parents=True, exist_ok=True)


def load_vcd(path, top):
    text = path.read_text()
    header, body = text.split("$enddefinitions $end", 1)
    scope, names, widths = [], {}, {}
    for line in header.splitlines():
        items = line.split()
        if not items:
            continue
        if items[0] == "$scope":
            scope.append(items[2])
        elif items[0] == "$upscope":
            scope.pop()
        elif items[0] == "$var" and scope == [top]:
            names[items[4]] = items[3]
            widths[items[4]] = int(items[2])
    unit = re.search(r"\$timescale\s+(\d+)\s*(\w+)\s+\$end", header)
    factor = int(unit[1]) * {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1, "ps": .001}[unit[2]]
    events, now, changes = [], 0, {}
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith("$"):
            continue
        if line.startswith("#"):
            if changes:
                events.append((now * factor, changes))
            now, changes = int(line[1:]), {}
        elif line[0] in "bB":
            bits, code = line[1:].split()
            changes[code] = int(bits, 2) if not re.search("[xXzZ]", bits) else None
        elif line[0] in "01xXzZ":
            changes[line[1:]] = int(line[0]) if line[0] in "01" else None
    if changes:
        events.append((now * factor, changes))
    return names, widths, events


def audit(path, top, is_update=False):
    names, widths, events = load_vcd(path, top)
    values, policy, staging = {}, [(False, 0, 0, False, False)] * 4, [None] * 4
    active, counts, commits = None, dict(accepted=0, completed=0, forwarded=0, denied=0, aborted=0), 0
    mem_stalled, rsp_stalled = None, None

    def word(s):
        return tuple(s[n] for n in ("mem_req_addr", "mem_req_write", "mem_req_wdata"))

    for time, change in events:
        before = values.copy()
        values.update(change)
        if before.get(names["clk"]) != 0 or values.get(names["clk"]) != 1:
            continue
        s = {name: before.get(code) for name, code in names.items()}
        if not s["rst_n"]:
            if active:
                counts["aborted"] += 1
            active, mem_stalled, rsp_stalled = None, None, None
            policy, staging = [(False, 0, 0, False, False)] * 4, [None] * 4
            continue
        if is_update and s["commit_ack"]:
            assert active is None, (path, time, "ack with outstanding transaction")
            assert all(p is not None for p in staging), (path, time, "partial policy")
            policy = staging.copy()
            commits += 1
        if mem_stalled is not None:
            assert s["mem_req_valid"] and word(s) == mem_stalled, (path, time, "unstable request")
        if rsp_stalled is not None:
            assert s["rsp_valid"] and (s["rsp_error"], s["rsp_rdata"]) == rsp_stalled, (path, time, "unstable response")
        mem_stalled = word(s) if s["mem_req_valid"] and not s["mem_req_ready"] else None
        rsp_stalled = (s["rsp_error"], s["rsp_rdata"]) if s["rsp_valid"] and not s["rsp_ready"] else None
        if s["mem_req_valid"]:
            assert active and active["allowed"] and not active["issued"], (path, time, "invalid forwarding")
            assert word(s) == active["payload"], (path, time, "payload mismatch")
            if s["mem_req_ready"]:
                active["issued"] = True
                counts["forwarded"] += 1
        if s["mem_rsp_valid"] and s["mem_rsp_ready"]:
            assert active and active["issued"] and not active["returned"]
            active["returned"] = True
            active["response"] = (s["mem_rsp_error"], 0 if s["mem_rsp_error"] or active["payload"][1] else s["mem_rsp_rdata"])
        if s["rsp_valid"]:
            assert active, (path, time, "unsolicited response")
            if active["allowed"]:
                assert active["returned"] and (s["rsp_error"], s["rsp_rdata"]) == active["response"]
            else:
                assert (s["rsp_error"], s["rsp_rdata"]) == (1, 0) and not active["issued"]
            if s["rsp_ready"]:
                counts["completed"] += 1
                active = None
        if s["req_valid"] and s["req_ready"]:
            assert active is None, (path, time, "multiple outstanding")
            address, wr = s["req_addr"], s["req_write"]
            allowed = False
            for en, lo, hi, rd, we in policy:
                if en and lo <= address <= hi:
                    allowed = bool((we if wr else rd) and address + 3 <= hi and address % 4 == 0)
                    break
            active = dict(allowed=allowed, issued=False, returned=False, payload=(address, wr, s["req_wdata"]))
            counts["accepted"] += 1
            counts["denied"] += not allowed
        if is_update and s["update_begin_valid"] and s["update_begin_ready"]:
            staging = [None] * 4
        if s["cfg_valid"] and s["cfg_ready"]:
            entry = (s["cfg_enable"], s["cfg_base"], s["cfg_limit"], s["cfg_read"], s["cfg_write"])
            (staging if is_update else policy)[s["cfg_index"]] = entry
    assert active is None and counts["accepted"] == counts["completed"] + counts["aborted"], (path, counts)
    return dict(trace=str(path.relative_to(ROOT)), sha256=hashlib.sha256(path.read_bytes()).hexdigest(), commits=commits, **counts)


def render(path, top, signals, target, title, start=0, stop=None):
    names, widths, events = load_vcd(path, top)
    stop = stop or events[-1][0]
    width, left, row, plot = 1480, 190, 38, 1250
    height = 110 + row * len(signals)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">', '<rect width="100%" height="100%" fill="#101827"/>', '<style>text{font:13px monospace;fill:#dce5f4}.label{font:14px sans-serif}.title{font:20px sans-serif;font-weight:600}</style>', f'<text x="20" y="29" class="title">{escape(title)}</text>', f'<text x="20" y="52">Source: {escape(str(path.relative_to(ROOT)))} | SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()[:16]}</text>']
    scale = plot / (stop - start)
    for n in range(11):
        at = start + (stop-start)*n/10
        x = left + (at-start)*scale
        svg += [f'<path d="M{x} 76V{height-20}" stroke="#263348"/>', f'<text x="{x}" y="74" text-anchor="middle">{at:.0f}ns</text>']
    for index, name in enumerate(signals):
        y = 100 + row * index
        svg.append(f'<text x="16" y="{y+5}" class="label">{name}</text>')
        vals, current, begun = [], None, start
        for at, change in events:
            if names[name] not in change:
                continue
            value = change[names[name]]
            if at <= start:
                current = value
            elif at < stop:
                vals.append((begun, at, current))
                begun, current = at, value
        vals.append((begun, stop, current))
        for a, b, value in vals:
            x1, x2 = left+(a-start)*scale, left+(b-start)*scale
            color = "#5be0b1" if value is not None else "#ffab70"
            if widths[name] == 1:
                level = y-9 if value else y+9
                svg.append(f'<path d="M{x1} {y-9}V{y+9}M{x1} {level}H{x2}" fill="none" stroke="{color}" stroke-width="1.5"/>')
            else:
                svg.append(f'<path d="M{x1} {y}l4 -10H{x2-4}l4 10 -4 10H{x1+4}Z" fill="#17253a" stroke="{color}"/>')
                if x2-x1 > 85:
                    label = "X" if value is None else f"{value:08x}"
                    svg.append(f'<text x="{(x1+x2)/2}" y="{y+4}" text-anchor="middle">{label}</text>')
    svg.append('</svg>')
    (OUT/target).write_text("\n".join(svg), encoding="utf-8")


if __name__ == "__main__":
    records = [audit(ROOT/"build/system.vcd", "tb_system")]
    render(ROOT/"build/system.vcd", "tb_system", ["rst_n","req_valid","req_ready","req_addr","req_write","mem_req_valid","mem_req_ready","mem_req_addr","rsp_valid","rsp_ready","rsp_error"], "static_waveform.svg", "Static enforcement: real simulation excerpt", stop=1600)
    for mode in (0, 1):
        for gap in (0, 4, 16):
            for stall in (0, 64):
                path = ROOT/f"build/comparison/mode{mode}_gap{gap}_stall{stall}/update.vcd"
                records.append(audit(path,"tb_update",True))
        path=ROOT/f"build/comparison/mode{mode}_gap4_stall0/update.vcd"
        render(path,"tb_update",["update_begin_valid","cfg_valid","cfg_ready","commit_valid","commit_ready","commit_ack","req_valid","req_ready","mem_req_valid","mem_req_ready","rsp_valid","rsp_error"],f"update_{mode}_waveform.svg",("Shadow-bank" if mode else "Stop-and-program")+" update: real simulation",stop=2000)
    (ROOT/"build/waveform_audit.json").write_text(json.dumps(records,indent=2))
    print(f"PASS: independently audited {len(records)} VCD traces; SVG excerpts in docs/figures")
