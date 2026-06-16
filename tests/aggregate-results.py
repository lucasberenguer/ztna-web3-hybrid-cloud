#!/usr/bin/env python3
import csv
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
PATTERN = re.compile(r"(?P<scenario>baseline|ztna)_vus(?P<vus>\d+)_rep(?P<rep>\d+)\.json$")
rows = []

for file in sorted(RESULTS.glob("*.json")):
    match = PATTERN.match(file.name)
    if not match:
        continue
    data = json.loads(file.read_text())
    metrics = data.get("metrics", {})
    duration = metrics.get("http_req_duration", {})
    requests = metrics.get("http_reqs", {})
    failed = metrics.get("http_req_failed", {})
    rows.append({
        "scenario": match.group("scenario"),
        "vus": int(match.group("vus")),
        "repetition": int(match.group("rep")),
        "avg_ms": duration.get("avg"),
        "median_ms": duration.get("med"),
        "p95_ms": duration.get("p(95)"),
        "p99_ms": duration.get("p(99)"),
        "requests": requests.get("count"),
        "requests_per_second": requests.get("rate"),
        "failure_rate": failed.get("value"),
        "source_file": file.name,
    })

if not rows:
    raise SystemExit("Nenhum resultado k6 encontrado em results/.")

raw_csv = RESULTS / "k6-raw.csv"
with raw_csv.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

summary_rows = []
keys = ["avg_ms", "median_ms", "p95_ms", "p99_ms", "requests_per_second", "failure_rate"]
for scenario in sorted({row["scenario"] for row in rows}):
    for vus in sorted({row["vus"] for row in rows if row["scenario"] == scenario}):
        group = [row for row in rows if row["scenario"] == scenario and row["vus"] == vus]
        summary = {"scenario": scenario, "vus": vus, "repetitions": len(group)}
        for key in keys:
            values = [float(row[key]) for row in group if row[key] is not None]
            summary[f"{key}_mean"] = statistics.fmean(values) if values else None
            summary[f"{key}_stdev"] = statistics.stdev(values) if len(values) > 1 else 0.0 if values else None
        summary_rows.append(summary)

summary_csv = RESULTS / "k6-summary.csv"
with summary_csv.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_rows[0].keys())
    writer.writeheader()
    writer.writerows(summary_rows)

print(f"Arquivos gerados: {raw_csv} e {summary_csv}")
