#!/usr/bin/env bash
# Build the four-LOD resource tree from the official N03 2026 nationwide GeoJSON.
# Layers: municipalities / prefectures / regions (polygons) and prefectureLines (borders + coastlines).
# Run with bash (including the Bash 3.2 supplied with macOS).
#
# Folder layout (DATA_ROOT = BoundaryData at the repository root, two levels above this script):
#   raw/         source data (never overwritten)
#   scripts/     this tool
#   normalized/  intermediate data per run
#   reports/     logs and checks per run
#   generated/   app resources (BoundaryData/)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${DATA_ROOT:-$(cd "$ROOT/../.." && pwd)}"
INPUT="${1:-$DATA_ROOT/raw/N03-20260101_GML/N03-20260101.geojson}"
HEAP_MB="${HEAP_MB:-8192}"
CLI="$ROOT/node_modules/mapshaper/bin/mapshaper"
HELPER="$ROOT/boundary_tools.mjs"
REGIONS="$ROOT/regions.json"
FINAL="$DATA_ROOT/generated/BoundaryData"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
WORK="$DATA_ROOT/normalized/$RUN_ID"
REPORTS="$DATA_ROOT/reports/$RUN_ID"
STAGE="$DATA_ROOT/generated/.BoundaryData-$RUN_ID"

command -v node >/dev/null 2>&1 || { echo "Install Node.js first." >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "Input file not found: $INPUT" >&2; exit 1; }
[[ -f "$CLI" ]] || { echo "Run: cd \"$ROOT\" && npm install --save-exact mapshaper" >&2; exit 1; }
[[ -f "$HELPER" ]] || { echo "Missing boundary_tools.mjs" >&2; exit 1; }
[[ -f "$REGIONS" ]] || { echo "Missing regions.json" >&2; exit 1; }
[[ ! -e "$FINAL" ]] || { echo "Output already exists; move it aside before rebuilding: $FINAL" >&2; exit 1; }
[[ "$HEAP_MB" =~ ^[0-9]+$ ]] || { echo "HEAP_MB must be an integer." >&2; exit 1; }
mkdir -p "$WORK" "$REPORTS" "$STAGE"
trap 'echo "Build failed. Inspect logs in: $REPORTS. Original input was not overwritten." >&2' ERR

# Call the CLI directly so a nonzero Mapshaper exit is propagated to this script.
ms() { node --max-old-space-size="$HEAP_MB" "$CLI" "$@"; }
ms -v > "$REPORTS/mapshaper-version.txt" 2>&1
ms -h dissolve > "$REPORTS/dissolve-help.txt" 2>&1
grep -q 'no-repair' "$REPORTS/dissolve-help.txt" || {
  echo "This script requires a Mapshaper version supporting dissolve no-repair." >&2
  exit 1
}
# Keep the exact region definition used by this run next to its reports.
cp "$REGIONS" "$REPORTS/regions.json"

# Export a small attribute-only JSON table. Do not JSON.parse the ~580 MB raw file.
echo "[1/6] Inspecting source attributes and region definition..."
ms -i "$INPUT" no-topology name=source -info \
  -o format=json "$WORK/source_attributes.json" \
  > "$REPORTS/01_source.log" 2>&1
node "$HELPER" audit "$WORK/source_attributes.json" "$REGIONS" "$REPORTS/source-audit.json"

# Lookup expressions generated from regions.json, so the region definition lives in one file.
REGION_OF_PREF_EXPR="$(node "$HELPER" region-expr "$REGIONS")"
REGION_NAME_EXPR="$(node "$HELPER" region-name-expr "$REGIONS")"

# Use one national topology. No independent per-prefecture simplification.
# -clean repairs the small gaps/overlaps between neighbouring municipalities in the source
# (a few metres wide). Without it those borders are not shared in the topology, so a prefecture
# dissolves into several touching pieces (e.g. Chiyoda/Chuo/Minato apart from the rest of Tokyo)
# and false "prefecture borders" appear inside it. The clean log records what was changed.
# Later dissolves keep no-repair: the topology is already clean at that point.
echo "[2/6] Normalizing, repairing gaps/overlaps and building the unsimplified national topology..."
ms -i "$INPUT" name=municipalities \
  -proj wgs84 \
  -each 'c=String(N03_007).trim(), p=c.slice(0,2), n=String(N03_004||"").trim()+String(N03_005||"").trim(), pn=String(N03_001||"").trim()' \
  -each "$REGION_OF_PREF_EXPR" \
  -filter-fields c,n,p,pn,r \
  -clean \
  -dissolve c no-repair copy-fields=n,p,pn,r \
  -explode \
  -each '_null=this.isNull, _bbox=this.bbox' \
  -o format=json "$WORK/baseline_parts.json" \
  -filter-fields c,n,p,pn,r \
  -o format=topojson no-quantization "$WORK/base.topojson" \
  > "$REPORTS/02_normalize.log" 2>&1
node "$HELPER" baseline "$WORK/baseline_parts.json" "$REPORTS/source-audit.json" "$REPORTS/baseline.json"

# Every LOD starts from the same UNSIMPLIFIED topology, not from another LOD.
# Exploded outer components are individually protected by keep-shapes; islands too small to ever be
# drawn at a LOD are removed afterwards by prune-and-round.
# Small holes and rounding artifacts still require review after export.
for spec in "0:2000" "1:500" "2:100" "3:20"; do
  lod="${spec%%:*}"
  meters="${spec#*:}"
  mdir="$STAGE/municipalities/lod${lod}_${meters}m"
  pdir="$STAGE/prefectures/lod${lod}_${meters}m"
  rdir="$STAGE/regions/lod${lod}_${meters}m"
  lines="$WORK/prefecture_lines_lod${lod}.geojson"
  mkdir -p "$mdir" "$pdir" "$rdir"
  echo "[3/6] Generating LOD $lod (${meters}m)..."

  # Derive prefecture and region exteriors from the SAME simplified municipality
  # geometry, so municipality, prefecture and region borders coincide exactly.
  common=(
    -i "$WORK/base.topojson" name=municipalities
    -simplify dp "interval=${meters}m" keep-shapes stats
    -dissolve c no-repair copy-fields=n,p,pn,r name=municipalities
    -dissolve p no-repair copy-fields=pn,r + name=prefectures
    -dissolve r no-repair target=prefectures + name=regions
    -each 'n=pn' target=prefectures
    -each "$REGION_NAME_EXPR" target=regions
    -filter-fields c,n,p,r target=municipalities
    -filter-fields p,n,r target=prefectures
    -filter-fields r,n target=regions
    -sort c target=municipalities
    -sort p target=prefectures
    -sort r target=regions
    # Prefecture borders and coastlines from the same municipality topology.
    # RANK 0 = outer boundary (coast), 1 = prefecture code changes, 2 = municipal border only (dropped).
    -lines p target=municipalities + name=prefectureLines
    -filter 'RANK < 2' target=prefectureLines
    -o target=prefectureLines format=geojson precision=0.000001 "$lines"
  )
  if [[ "$lod" == "0" ]]; then
    ms "${common[@]}" \
      -o target=municipalities format=geojson precision=0.000001 bbox \
         "$mdir/municipality_jp_lod0.geojson" \
      -o target=prefectures format=geojson precision=0.000001 bbox \
         "$pdir/prefecture_jp_lod0.geojson" \
      -o target=regions format=geojson precision=0.000001 bbox \
         "$rdir/region_jp_lod0.geojson" \
      > "$REPORTS/03_lod${lod}.log" 2>&1
  else
    # An empty layer name prevents Mapshaper adding an unwanted filename prefix.
    # Municipalities and prefectures are split per prefecture; regions per region.
    ms "${common[@]}" \
      -target municipalities name= \
      -split "\"municipality_\" + p + \"_lod${lod}\"" \
      -o format=geojson extension=geojson precision=0.000001 bbox "$mdir/" \
      -target prefectures name= \
      -split "\"prefecture_\" + p + \"_lod${lod}\"" \
      -o format=geojson extension=geojson precision=0.000001 bbox "$pdir/" \
      -target regions name= \
      -split "\"region_\" + r + \"_lod${lod}\"" \
      -o format=geojson extension=geojson precision=0.000001 bbox "$rdir/" \
      > "$REPORTS/03_lod${lod}.log" 2>&1
  fi
  # Give each line one owner prefecture (a shared border is stored once) and split per prefecture.
  node "$HELPER" prefecture-lines "$lines" "$pdir" "$STAGE/prefectureLines" "$lod" \
    >> "$REPORTS/03_lod${lod}.log" 2>&1
  # keep-shapes above keeps every island. Drop the ones the app can never draw at this LOD, then round
  # coarse LODs to fewer digits. Both must run after prefecture-lines, which needs every prefecture vertex
  # at full precision (rounding in Mapshaper drops collapsed island rings from polygons but not from lines).
  node "$HELPER" prune-and-round "$STAGE" "$lod" \
    >> "$REPORTS/03_lod${lod}.log" 2>&1
done

echo "[4/6] Checking output files and writing manifest..."
node "$HELPER" manifest "$STAGE" "$REPORTS/source-audit.json" \
  "$REPORTS/baseline.json" "$REPORTS/output-checks.json" \
  "$REPORTS/mapshaper-version.txt"

echo "[5/6] Recording the source checksum..."
node "$HELPER" hash "$INPUT" "$REPORTS/source-sha256.json"

echo "[6/6] Publishing generated resources..."
mv "$STAGE" "$FINAL"

# Intermediate data is ~400 MB per run and fully reproducible, so keep only this run's.
# Only run-ID-shaped folders are removed; reports/ are small and all kept as history.
for old in "$DATA_ROOT"/normalized/*; do
  name="$(basename "$old")"
  if [[ -d "$old" && "$name" != "$RUN_ID" && "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]; then
    rm -rf "$old"
    echo "Removed old intermediate data: normalized/$name"
  fi
done

echo "Resources: $FINAL"
echo "Reports:   $REPORTS"
echo "Copy only BoundaryData into the app resources. Spatial QA and release review remain necessary."
