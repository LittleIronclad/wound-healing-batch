/*
 * Batch_Enhance_Contrast.ijm — contrast enhancement for whole folder trees (figure preparation)
 * Author: Alexey Potemkin, https://github.com/LittleIronclad/wound-healing-batch
 *
 * Mirrors the sub-folder structure of the input folder in the output folder and applies
 * Process › Enhance Contrast to every image. Useful for making scratch-assay images readable in
 * figures. It is NOT needed before Wound_Healing_Batch.ijm, which enhances contrast internally.
 *
 * USAGE
 *   GUI:      Plugins › Macros › Run…
 *   Headless: ImageJ -batch Batch_Enhance_Contrast.ijm "input=[/in] output=[/out] saturated=0.35 normalize=yes format=tiff"
 */

var saturated = 0.35;     // % saturated pixels
var normalize = true;     // true: stretch pixel values; false: change only the display range (LUT)
var format = "TIFF";      // TIFF keeps full quality; PNG or JPEG for slides

args = getArgument();
if (args != "") {
    inputDir  = argValue(args, "input", "");
    outputDir = argValue(args, "output", "");
    saturated = parseFloat(argValue(args, "saturated", saturated));
    normalize = (toLowerCase(argValue(args, "normalize", "yes")) == "yes");
    format    = toUpperCase(argValue(args, "format", format));
    if (inputDir == "" || outputDir == "") exit("Headless mode needs input=[…] and output=[…]");
} else {
    Dialog.create("Batch contrast enhancement");
    Dialog.addDirectory("Input folder (images and/or sub-folders)", "");
    Dialog.addDirectory("Output folder", "");
    Dialog.addNumber("Saturated pixels (%)", saturated);
    Dialog.addCheckbox("Normalize (change pixel values)", normalize);
    Dialog.addChoice("Save as", newArray("TIFF", "PNG", "JPEG"), format);
    Dialog.show();
    inputDir  = Dialog.getString();
    outputDir = Dialog.getString();
    saturated = Dialog.getNumber();
    normalize = Dialog.getCheckbox();
    format    = Dialog.getChoice();
}
inputDir = withSlash(inputDir);
outputDir = withSlash(outputDir);
if (!File.isDirectory(outputDir)) File.makeDirectory(outputDir);

setBatchMode(true);
print("\\Clear");
n = processFolder(inputDir, outputDir);
setBatchMode(false);
print("Done: " + n + " images → " + outputDir);
if (args == "") showMessage("Batch contrast enhancement", "Processed " + n + " images.");


function processFolder(inDir, outDir) {
    count = 0;
    list = getFileList(inDir);
    for (i = 0; i < list.length; i++) {
        item = list[i];
        if (startsWith(item, ".")) continue;
        if (endsWith(item, "/")) {
            File.makeDirectory(outDir + item);
            count = count + processFolder(inDir + item, outDir + item);
        } else if (isImage(item)) {
            open(inDir + item);
            options = "saturated=" + saturated;
            if (normalize) options = options + " normalize";
            run("Enhance Contrast...", options);
            ext = ".tif";
            if (format == "PNG") ext = ".png";
            if (format == "JPEG") ext = ".jpg";
            saveAs(format, outDir + baseName(item) + ext);
            close();
            count++;
        }
    }
    print("  " + inDir + ": done");
    return count;
}

function isImage(name) {
    lower = toLowerCase(name);
    extensions = newArray(".tif", ".tiff", ".jpg", ".jpeg", ".png", ".bmp");
    for (e = 0; e < extensions.length; e++)
        if (endsWith(lower, extensions[e])) return true;
    return false;
}

function baseName(name) {
    dot = lastIndexOf(name, ".");
    if (dot > 0) return substring(name, 0, dot);
    return name;
}

function withSlash(dir) {
    if (!endsWith(dir, "/") && !endsWith(dir, File.separator)) dir = dir + File.separator;
    return dir;
}

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
