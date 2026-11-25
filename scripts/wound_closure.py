#!/usr/bin/env python3
"""Turn all_results.csv from Wound_Healing_Batch.ijm into wound-closure kinetics.

For every scratch position (the same image name with the time point removed) the earliest image
is the reference (t0):

    wound closure (%)      = (A_t0 − A_t) / A_t0 × 100
    migration rate (µm/h)  = (W_t0 − W_t) / (t − t0)          (Suarez-Arnedo et al., 2020)

Time points are parsed from file names: IncuCyte style "…_00d12h00m…" or any "12h" / "12 h" /
"12hr" token. Use --time-regex for other naming schemes; its first capture group is read as hours.

Outputs (next to the input file unless --out is given):
    closure_per_image.csv, closure_summary.csv (mean ± SEM per folder and time), closure_plot.png

Usage:
    python wound_closure.py results/all_results.csv
    python wound_closure.py all_results.csv --time-regex "T(\\d+)" --out analysis/
"""
import argparse
import re
from pathlib import Path

import numpy as np
import pandas as pd

INCUCYTE = re.compile(r"(\d+)d(\d+)h(\d+)m")
HOURS = re.compile(r"(?<![\d.])(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?)(?![a-z])", re.IGNORECASE)


def parse_time(name: str, custom: re.Pattern | None):
    """Return (hours, name with the time token removed) or (nan, name)."""
    stem = Path(name).stem
    if custom is not None:
        m = custom.search(stem)
        return (float(m.group(1)), clean(stem[:m.start()] + stem[m.end():])) if m else (np.nan, stem)
    m = INCUCYTE.search(stem)
    if m:
        d, h, mi = map(int, m.groups())
        return d * 24 + h + mi / 60, clean(stem[:m.start()] + stem[m.end():])
    m = HOURS.search(stem)
    if m:
        return float(m.group(1)), clean(stem[:m.start()] + stem[m.end():])
    return np.nan, stem


def clean(s: str) -> str:
    return re.sub(r"[_\-\s.]+", "_", s).strip("_")


def column(df, prefix):
    cols = [c for c in df.columns if c.startswith(prefix)]
    if not cols:
        raise SystemExit(f"Column starting with '{prefix}' not found in {list(df.columns)}")
    return cols[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results", type=Path, help="all_results.csv produced by Wound_Healing_Batch.ijm")
    ap.add_argument("--time-regex", help="regex whose first group is the time in hours")
    ap.add_argument("--out", type=Path, help="output folder (default: next to the input)")
    a = ap.parse_args()

    df = pd.read_csv(a.results)
    area_col, width_col = column(df, "Area ("), column(df, "Mean width")
    unit = width_col[width_col.find("(") + 1:width_col.find(")")]
    custom = re.compile(a.time_regex) if a.time_regex else None
    parsed = df["Image"].map(lambda n: parse_time(n, custom))
    df["time_h"] = [p[0] for p in parsed]
    df["position"] = [p[1] for p in parsed]

    missing = df["time_h"].isna()
    if missing.any():
        print(f"Warning: no time point found in {missing.sum()} file names, e.g. {df.loc[missing, 'Image'].iloc[0]!r}"
              " — they are skipped (use --time-regex).")
    df = df[~missing & (df["Status"] == "ok")].copy()
    if df.empty:
        raise SystemExit("Nothing to analyse.")

    rows = []
    for (folder, pos), g in df.groupby(["Folder", "position"]):
        g = g.sort_values("time_h")
        t0, a0, w0 = g.iloc[0][["time_h", area_col, width_col]]
        for _, r in g.iterrows():
            dt = r.time_h - t0
            rows.append({"Folder": folder, "position": pos, "Image": r.Image, "time_h": r.time_h,
                         "area": r[area_col], "mean_width": r[width_col],
                         "closure_pct": (a0 - r[area_col]) / a0 * 100 if a0 > 0 else np.nan,
                         f"migration_rate_{unit}_per_h": (w0 - r[width_col]) / dt if dt > 0 else np.nan})
    per_image = pd.DataFrame(rows)

    def sem(x):
        return x.std(ddof=1) / np.sqrt(x.count()) if x.count() > 1 else np.nan

    summary = (per_image.groupby(["Folder", "time_h"])
               .agg(n=("closure_pct", "count"), closure_mean=("closure_pct", "mean"), closure_sem=("closure_pct", sem),
                    width_mean=("mean_width", "mean"), width_sem=("mean_width", sem))
               .reset_index())

    out = a.out or a.results.parent
    out.mkdir(parents=True, exist_ok=True)
    per_image.to_csv(out / "closure_per_image.csv", index=False)
    summary.to_csv(out / "closure_summary.csv", index=False)
    print(summary.round(2).to_string(index=False))

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(6.5, 4.2))
        for folder, s in summary.groupby("Folder"):
            ax.errorbar(s.time_h, s.closure_mean, yerr=s.closure_sem.fillna(0), marker="o", capsize=3,
                        label=f"{folder} (n={int(s.n.max())})")
        ax.set(xlabel="Time (h)", ylabel="Wound closure (%)", title="Scratch-assay wound closure (mean ± SEM)")
        ax.axhline(0, color="grey", lw=0.8)
        ax.legend(frameon=False, fontsize=8)
        ax.spines[["top", "right"]].set_visible(False)
        fig.savefig(out / "closure_plot.png", dpi=160, bbox_inches="tight")
        print(f"\nSaved to {out}/: closure_per_image.csv, closure_summary.csv, closure_plot.png")
    except ImportError:
        print(f"\nSaved to {out}/: closure_per_image.csv, closure_summary.csv (install matplotlib for the plot)")


if __name__ == "__main__":
    main()
