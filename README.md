# Wound Healing Batch — scratch-assay quantification for whole folders in ImageJ / Fiji

![ImageJ](https://img.shields.io/badge/ImageJ%20%2F%20Fiji-macro-blue)
![License](https://img.shields.io/badge/license-MIT%20(batch%20code)-green)

Batch tools for the **in vitro scratch (wound-healing) assay**. They measure wound area, area fraction, mean wound width and width variability for **every image in a folder tree in one run**, and write ready-to-analyse tables, quality-control images and wound-closure kinetics.

> **Built on [Wound_healing_size_tool](https://github.com/AlejandraArnedo/Wound-healing-size-tool)** by Suarez-Arnedo A., Torres Figueroa F., Clavijo C., Arbeláez P., Cruz J.C. & Muñoz-Camargo C.: *"An image J plugin for the high throughput image analysis of in vitro scratch wound healing assays"*, **PLoS ONE 15(7): e0232565 (2020)**, [doi:10.1371/journal.pone.0232565](https://doi.org/10.1371/journal.pone.0232565).
> The segmentation and width-measurement algorithm is theirs. **If you use these tools, please cite their paper.**

## Why

The original plugin analyses one image (or one stack) at a time. Results are copied out of the Results window by hand. A typical assay (several cell lines × wells × fields × 4–6 time points) quickly becomes hundreds of images. These macros run the same algorithm over a whole folder tree and keep the output organised:

- **one run for many folders**: one sub-folder per condition, well or cell line;
- **tables**: one CSV per sub-folder plus a combined `all_results.csv`;
- **QC images**: every original image is saved with the detected wound outlined, so a wrong segmentation is easy to spot;
- **fixed pixel size** for uncalibrated images (e.g. JPEG exports from IncuCyte);
- **parameter log** (`parameters.txt`) for reproducibility;
- **headless mode** for scripted runs;
- **wound-closure kinetics**: `scripts/wound_closure.py` turns the table into % closure and migration rate per condition over time.

## Contents

| File | What it is |
|---|---|
| [`macros/Wound_Healing_Batch.ijm`](macros/Wound_Healing_Batch.ijm) | **Main tool.** Batch analysis of a folder and its sub-folders → CSV tables + QC images |
| [`macros/Wound_healing_size_tool_fixed.ijm`](macros/Wound_healing_size_tool_fixed.ijm) | The original interactive toolset (single image + stack) with bug fixes. Useful for tuning parameters on a few images |
| [`macros/Batch_Enhance_Contrast.ijm`](macros/Batch_Enhance_Contrast.ijm) | Contrast enhancement for a whole folder tree, keeping the folder structure (for figures) |
| [`scripts/wound_closure.py`](scripts/wound_closure.py) | % wound closure and migration rate per position, condition and time point, with a plot |

## Quick start

1. Arrange the images, e.g. one sub-folder per condition:
   ```
   scratch_assay/
   ├── control/       VID1_A1_1_00d00h00m.jpg, VID1_A1_1_00d12h00m.jpg, …
   ├── drug_low/      …
   └── drug_high/     …
   ```
   Images directly inside `scratch_assay/` are processed too.
2. In Fiji: **Plugins › Macros › Run…** → `Wound_Healing_Batch.ijm`.
3. Choose the input and output folders and the parameters (below) → **OK**.
4. Open `qc/` and check that the cyan outline follows the wound in every image.

**Output**
```
results/
├── control.csv, drug_low.csv, drug_high.csv   one table per sub-folder
├── all_results.csv                            everything in one table
├── parameters.txt                             settings, ImageJ version, date
└── qc/<sub-folder>/<image>.jpg                original image + detected wound outline
```

| Folder | Image | Area (um^2) | Area (%) | Mean width (um) | Width SD (um) | Angle (deg) | Status |
|---|---|---|---|---|---|---|---|

Units follow the image calibration, or µm if a pixel size is given. Images where no wound is found get `Status = no wound detected` and a red label in the QC image.

## Parameters

The definitions follow the original manual.

| Parameter | Meaning | Tip |
|---|---|---|
| Variance window radius | Radius of the variance filter that separates empty from cell-covered areas | Must be large enough that noise does not look like texture; 10–30 px for 10× images |
| Threshold value | Variance below this value = empty (wound) | The most sensitive parameter: tune it on a few images first |
| Percentage of saturated pixels | Contrast enhancement before filtering (> 0) | Increase for low-contrast phase images |
| Minimum particle size | Ignore empty specks smaller than this (px²) | — |
| Scratch is diagonal? | Corrects the mean width for the inclination of the scratch | "Yes" unless the scratch is perfectly vertical |
| Pixel size (µm/px) | Overrides the image calibration; 0 = use the calibration in the file | Needed for JPEG/PNG exports without metadata |

The scratch is expected to run **vertically**. Rotate horizontal scratches first, for example with the Rotate tool in `Wound_healing_size_tool_fixed.ijm`. A good workflow is to tune the parameters on 3–5 representative images with the interactive tool, then run the batch macro.

## Wound-closure kinetics

```bash
pip install pandas matplotlib
python scripts/wound_closure.py results/all_results.csv
```

Time points are read from file names: IncuCyte style `…_01d12h00m…` or any `12h` / `12 h` / `12hr` token. Use `--time-regex` for other schemes. The same name without the time token identifies one scratch position, and its earliest image is the reference:

- wound closure (%) = (A<sub>t0</sub> − A<sub>t</sub>) / A<sub>t0</sub> × 100
- migration rate = (W<sub>t0</sub> − W<sub>t</sub>) / (t − t0), in µm/h

The script writes `closure_per_image.csv`, `closure_summary.csv` (mean ± SEM per folder and time point) and `closure_plot.png`.

## Headless use *(experimental)*

```bash
ImageJ-macosx -batch macros/Wound_Healing_Batch.ijm \
  "input=[/path/to/scratch_assay] output=[/path/to/results] radius=20 threshold=100 saturated=0.001 min_size=100 diagonal=yes pixel_size=0 qc=yes"
```
Use `[…]` for paths with spaces. The ROI Manager needs a display; on a server without one, run under `xvfb-run`.

## Changes relative to the original tool

- Batch processing of a folder and its sub-folders in one run, with per-folder and combined CSV export.
- QC overlay images, parameter log, optional fixed pixel size, headless mode.
- Skips hidden and system files (e.g. macOS `._*`) that used to break batch runs.
- Interactive toolset: the options dialog is a callable function; the stack tool duplicates only the current slice; guards for images without a detectable wound; robust handling of edge arrays of unequal length.
- The segmentation (contrast → variance filter → threshold → fill holes → largest particle) and the width / diagonal-correction calculations are unchanged.

## License and attribution

The batch-processing code, the contrast macro and the Python script are by Alexey Potemkin and released under the [MIT License](LICENSE). The wound segmentation and width algorithm, and the interactive toolset in `Wound_healing_size_tool_fixed.ijm`, are by Suarez-Arnedo et al. (2020). Their original repository does not state a licence, so those parts remain the work of the original authors and are redistributed here with attribution. Please cite:

> Suarez-Arnedo A, Torres Figueroa F, Clavijo C, Arbeláez P, Cruz JC, Muñoz-Camargo C (2020). An image J plugin for the high throughput image analysis of in vitro scratch wound healing assays. *PLoS ONE* 15(7): e0232565. https://doi.org/10.1371/journal.pone.0232565

## Author

**Alexey Potemkin**, MSc Bioinformatics student, University of Tübingen · [GitHub](https://github.com/LittleIronclad) · [LinkedIn](https://www.linkedin.com/in/alexey-potemkin-567bb3364/)
