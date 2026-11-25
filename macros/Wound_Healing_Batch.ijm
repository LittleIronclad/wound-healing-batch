/*
 * Wound_Healing_Batch.ijm — batch quantification of scratch (wound-healing) assay images
 * ---------------------------------------------------------------------------------------
 * Author of the batch tool: Alexey Potemkin (2025–2026), https://github.com/LittleIronclad/wound-healing-batch
 *
 * The segmentation and width algorithm is taken from Wound_healing_size_tool by
 * Suarez-Arnedo A. et al. (2020) PLoS ONE 15(7): e0232565, doi:10.1371/journal.pone.0232565,
 * https://github.com/AlejandraArnedo/Wound-healing-size-tool — please cite their paper.
 *
 * What this macro adds: processing of a whole folder tree in one run, one CSV per sub-folder plus
 * a combined CSV, quality-control overlays, a fixed pixel size for uncalibrated images, a
 * parameter log, and a headless mode.
 *
 * USAGE
 *   GUI:      Plugins › Macros › Run…  → choose this file → fill in the dialog.
 *   Headless: ImageJ -batch Wound_Healing_Batch.ijm "input=[/path/in] output=[/path/out] radius=20
 *             threshold=100 saturated=0.001 min_size=100 diagonal=yes pixel_size=0 qc=yes"
 *
 * INPUT  a folder with images and/or sub-folders of images (one level deep; e.g. one sub-folder
 *        per condition or per well). Supported: .tif .tiff .jpg .jpeg .png .bmp
 * OUTPUT <output>/<sub-folder>.csv, <output>/all_results.csv, <output>/parameters.txt,
 *        <output>/qc/<sub-folder>/<image>.jpg (original image with the detected wound outlined)
 */

// ── Defaults (the same as in the original tool) ──────────────────────────────
// Declared with "var" so that the functions below can see them.
var radius = 20;          // variance filter radius (px)
var threshold = 100;      // variance threshold: pixels below it count as "empty" (wound)
var saturated = 0.001;    // % saturated pixels for contrast enhancement (must be > 0)
var minSize = 100;        // minimum particle size (px²)
var diagonal = "Yes";     // correct the mean width for scratch inclination
var pixelSize = 0;        // µm per pixel; 0 = use the calibration stored in each image
var saveQC = true;        // save overlay images for visual checking

// ── Parameters: from the command line (headless) or from a dialog ────────────
args = getArgument();
if (args != "") {
    inputDir  = argValue(args, "input", "");
    outputDir = argValue(args, "output", "");
    radius    = parseFloat(argValue(args, "radius", radius));
    threshold = parseFloat(argValue(args, "threshold", threshold));
    saturated = parseFloat(argValue(args, "saturated", saturated));
    minSize   = parseFloat(argValue(args, "min_size", minSize));
    pixelSize = parseFloat(argValue(args, "pixel_size", pixelSize));
    diagonal  = yesNo(argValue(args, "diagonal", diagonal));
    saveQC    = (yesNo(argValue(args, "qc", "yes")) == "Yes");
    if (inputDir == "" || outputDir == "") exit("Headless mode needs input=[…] and output=[…]");
} else {
    Dialog.create("Wound healing — batch analysis");
    Dialog.addDirectory("Input folder (images or sub-folders)", "");
    Dialog.addDirectory("Output folder", "");
    Dialog.addMessage("Segmentation (see Suarez-Arnedo et al., 2020)");
    Dialog.addNumber("Variance window radius (px)", radius);
    Dialog.addSlider("Threshold value", 0, 255, threshold);
    Dialog.addNumber("Percentage of saturated pixels", saturated);
    Dialog.addNumber("Minimum wound particle size (px²)", minSize);
    Dialog.addChoice("Scratch is diagonal (correct width)?", newArray("Yes", "No"), diagonal);
    Dialog.addMessage("Scale");
    Dialog.addNumber("Pixel size (µm/px), 0 = use image calibration", pixelSize, 4, 8, "");
    Dialog.addCheckbox("Save QC images with the detected wound outlined", saveQC);
    Dialog.show();
    inputDir  = Dialog.getString();
    outputDir = Dialog.getString();
    radius    = Dialog.getNumber();
    threshold = Dialog.getNumber();
    saturated = Dialog.getNumber();
    minSize   = Dialog.getNumber();
    diagonal  = Dialog.getChoice();
    pixelSize = Dialog.getNumber();
    saveQC    = Dialog.getCheckbox();
}
inputDir = withSlash(inputDir);
outputDir = withSlash(outputDir);
if (!File.isDirectory(inputDir)) exit("Input folder not found:\n" + inputDir);
if (!File.isDirectory(outputDir)) File.makeDirectory(outputDir);
if (saturated <= 0) exit("Percentage of saturated pixels must be greater than zero.");

// ── Collect folders: the input folder itself (if it holds images) + its sub-folders ──
folders = newArray(0);
if (countImages(inputDir) > 0) folders = Array.concat(folders, "");
entries = getFileList(inputDir);
for (i = 0; i < entries.length; i++) {
    if (endsWith(entries[i], "/") && !startsWith(entries[i], "."))
        folders = Array.concat(folders, entries[i]);
}
if (folders.length == 0) exit("No images found in\n" + inputDir);

setBatchMode(true);
setOption("BlackBackground", true);
run("Set Measurements...", "area mean min fit redirect=None decimal=4");
roiManager("reset");
print("\\Clear");
print("Wound healing batch analysis — " + folders.length + " folder(s)");
start = getTime();

ALL = "all_results";
Table.create(ALL);
nImagesTotal = 0;
nNoWound = 0;

for (f = 0; f < folders.length; f++) {
    folderName = folders[f];
    if (folderName == "") label = File.getName(substring(inputDir, 0, lengthOf(inputDir) - 1));
    else label = substring(folderName, 0, lengthOf(folderName) - 1);
    dir = inputDir + folderName;
    files = getFileList(dir);
    Array.sort(files);

    qcDir = outputDir + "qc" + File.separator + label + File.separator;
    if (saveQC) {
        File.makeDirectory(outputDir + "qc");
        File.makeDirectory(qcDir);
    }
    T = label;
    Table.create(T);
    print("  " + label + " …");

    for (j = 0; j < files.length; j++) {
        name = files[j];
        if (!isImage(name)) continue;
        open(dir + name);
        result = analyse(name, qcDir);   // "area|areaPct|width|sd|angle|unit|status"
        r = split(result, "|");
        addRow(T, label, name, r);
        addRow(ALL, label, name, r);
        nImagesTotal++;
        if (r[6] != "ok") nNoWound++;
        run("Close All");
        roiManager("reset");
    }
    Table.save(outputDir + label + ".csv", T);
    if (isOpen(T)) { selectWindow(T); run("Close"); }
}
Table.save(outputDir + "all_results.csv", ALL);

params = "Wound_Healing_Batch.ijm\n"
    + "date: " + timestamp() + "\n"
    + "ImageJ: " + getVersion() + "\n"
    + "input: " + inputDir + "\n"
    + "variance radius (px): " + radius + "\n"
    + "threshold: " + threshold + "\n"
    + "saturated pixels (%): " + saturated + "\n"
    + "min particle size (px^2): " + minSize + "\n"
    + "diagonal correction: " + diagonal + "\n"
    + "pixel size (um/px, 0 = image calibration): " + pixelSize + "\n"
    + "images processed: " + nImagesTotal + "; no wound detected: " + nNoWound + "\n";
File.saveString(params, outputDir + "parameters.txt");
setBatchMode(false);

msg = "Processed " + nImagesTotal + " images in " + folders.length + " folder(s) in "
      + d2s((getTime() - start) / 1000, 1) + " s.\nNo wound detected: " + nNoWound
      + "\nResults: " + outputDir;
print(msg);
if (args == "") showMessage("Wound healing — done", msg);


// ═════════════════════════════════════════════════════════════════════════════
// Analysis of one image (algorithm of Wound_healing_size_tool, Suarez-Arnedo et al., 2020)
// ═════════════════════════════════════════════════════════════════════════════
function analyse(name, qcDir) {
    orig = getImageID();
    getPixelSize(unit, pw, ph);
    if (pixelSize > 0) { pw = pixelSize; unit = "micron"; }
    w = getWidth();
    h = getHeight();

    run("Select None");
    run("Duplicate...", "title=wound_mask");
    run("8-bit");
    run("Set Scale...", "distance=0 known=0 unit=pixel");
    run("Enhance Contrast...", "saturated=" + saturated + " normalize");
    run("Variance...", "radius=" + radius);
    setThreshold(0, threshold);
    run("Convert to Mask");
    run("Fill Holes");
    run("Select All");
    roiManager("reset");
    run("Analyze Particles...", "size=" + minSize + "-Infinity circularity=0.00-1.00 show=Nothing add");

    n = roiManager("count");
    if (n == 0) {
        close("wound_mask");
        if (saveQC) saveOverlay(orig, -1, qcDir, name);
        return "0|0|NaN|NaN|NaN|" + unit + "|no wound detected";
    }

    // the wound = the largest particle
    largest = 0; best = -1;
    for (k = 0; k < n; k++) {
        roiManager("select", k);
        a = getValue("Area");
        if (a > best) { best = a; largest = k; }
    }
    roiManager("select", largest);

    // mean width and its SD from the left/right edges of the wound ROI
    Roi.getContainedPoints(xp, yp);
    if (xp.length < 3) {
        close("wound_mask");
        if (saveQC) saveOverlay(orig, -1, qcDir, name);
        return "0|0|NaN|NaN|NaN|" + unit + "|wound too small";
    }
    mins = edgeMin(xp);
    maxs = edgeMax(xp);
    m = minOf(mins.length, maxs.length);
    diffs = newArray(m);
    for (k = 0; k < m; k++) diffs[k] = maxs[k] - mins[k];
    Array.getStatistics(diffs, lo, hi, meanW, sdW);

    List.setMeasurements;
    angle = List.getValue("Angle");
    corr = 1;
    if (diagonal == "Yes") corr = sin((90 - (angle - 90)) * PI / 180);

    areaPx = getValue("Area");                       // image is uncalibrated here → pixels
    area = areaPx * pw * pw;
    areaPct = areaPx / (w * h) * 100;
    width = meanW * pw * corr;
    sd = sdW * pw;

    close("wound_mask");
    if (saveQC) saveOverlay(orig, largest, qcDir, name);
    return "" + area + "|" + areaPct + "|" + width + "|" + sd + "|" + angle + "|" + unit + "|ok";
}

function saveOverlay(imageID, roiIndex, qcDir, name) {
    selectImage(imageID);
    run("Select None");
    if (roiIndex >= 0) {
        roiManager("select", roiIndex);
        Overlay.addSelection("cyan", maxOf(2, round(getWidth() / 400)));
        run("Select None");
    } else {
        setFont("SansSerif", maxOf(14, round(getWidth() / 30)), "bold");
        setColor("red");
        Overlay.drawString("no wound detected", 10, maxOf(20, round(getWidth() / 25)));
    }
    run("Flatten");
    saveAs("Jpeg", qcDir + baseName(name) + ".jpg");
    close();
    selectImage(imageID);
}

// Local minima / maxima of the x-coordinates of the ROI points = left / right wound edges
// (functions as in the original tool).
function edgeMin(arr) {
    out = newArray(0);
    if (arr.length > 0) out = Array.concat(out, arr[0]);
    for (x = 1; x < arr.length - 2; x++)
        if (arr[x - 1] > arr[x] && arr[x] < arr[x + 1]) out = Array.concat(out, arr[x]);
    return out;
}

function edgeMax(arr) {
    out = newArray(0);
    for (x = 1; x < arr.length - 2; x++)
        if (arr[x - 1] < arr[x] && arr[x] > arr[x + 1]) out = Array.concat(out, arr[x]);
    if (arr.length > 0) out = Array.concat(out, arr[arr.length - 1]);
    return out;
}

// ── Helpers ──────────────────────────────────────────────────────────────────
function addRow(table, folder, image, r) {
    unit = r[5];
    if (unit == "micron") unit = "um";
    row = Table.size(table);
    Table.set("Folder", row, folder, table);
    Table.set("Image", row, image, table);
    Table.set("Area (" + unit + "^2)", row, parseFloat(r[0]), table);
    Table.set("Area (%)", row, parseFloat(r[1]), table);
    Table.set("Mean width (" + unit + ")", row, parseFloat(r[2]), table);
    Table.set("Width SD (" + unit + ")", row, parseFloat(r[3]), table);
    Table.set("Angle (deg)", row, parseFloat(r[4]), table);
    Table.set("Status", row, r[6], table);
}

function isImage(name) {
    if (startsWith(name, ".") || endsWith(name, "/")) return false;   // skips macOS "._" files
    lower = toLowerCase(name);
    extensions = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".png", ".bmp");
    for (e = 0; e < extensions.length; e++)
        if (endsWith(lower, extensions[e])) return true;
    return false;
}

function countImages(dir) {
    list = getFileList(dir);
    c = 0;
    for (i = 0; i < list.length; i++) if (isImage(list[i])) c++;
    return c;
}

function baseName(name) {
    dot = lastIndexOf(name, ".");
    if (dot > 0) return substring(name, 0, dot);
    return name;
}

function withSlash(dir) {
    if (dir == "") return dir;
    if (!endsWith(dir, "/") && !endsWith(dir, File.separator)) dir = dir + File.separator;
    return dir;
}

function yesNo(value) {
    v = toLowerCase("" + value);
    if (v == "yes" || v == "true" || v == "1") return "Yes";
    return "No";
}

// Reads key=value or key=[value with spaces] from the argument string.
function argValue(args, key, def) {
    s = " " + args;
    i = indexOf(s, " " + key + "=");
    if (i < 0) return "" + def;
    v = substring(s, i + lengthOf(key) + 2);
    if (startsWith(v, "[")) return substring(v, 1, indexOf(v, "]"));
    e = indexOf(v, " ");
    if (e < 0) return v;
    return substring(v, 0, e);
}

function timestamp() {
    getDateAndTime(year, month, dow, day, hour, minute, second, msec);
    return "" + year + "-" + IJ.pad(month + 1, 2) + "-" + IJ.pad(day, 2) + " " + IJ.pad(hour, 2) + ":" + IJ.pad(minute, 2);
}
