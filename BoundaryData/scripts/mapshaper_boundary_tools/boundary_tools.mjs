#!/usr/bin/env node
/** Attribute audit, region lookup, structural output checks and app-specific manifest generation.
 * No external dependencies. Geometry repair is done by Mapshaper -clean in build_boundaries.sh, not here.
 * The large ORIGINAL GeoJSON is read only as a byte stream for its checksum.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const LODS = [
  { id: 0, intervalMeters: 2000, minWidthMeters: 800000, maxWidthMeters: null },
  { id: 1, intervalMeters: 500, minWidthMeters: 200000, maxWidthMeters: 800000 },
  { id: 2, intervalMeters: 100, minWidthMeters: 50000, maxWidthMeters: 200000 },
  { id: 3, intervalMeters: 20, minWidthMeters: 0, maxWidthMeters: 50000 },
];
// Written to manifest.json; the app switches LOD with these (hysteresis between zoom in and out).
const LOD_TRANSITIONS = [
  { coarseLOD: 0, fineLOD: 1, zoomInBelowMeters: 700000, zoomOutAboveMeters: 900000 },
  { coarseLOD: 1, fineLOD: 2, zoomInBelowMeters: 180000, zoomOutAboveMeters: 230000 },
  { coarseLOD: 2, fineLOD: 3, zoomInBelowMeters: 45000, zoomOutAboveMeters: 60000 },
];
// The app never draws a piece smaller than 1/100 of the screen width (BoundaryPieceFilter.screenResolution
// in WAGhack). Keep this equal to it: a larger value here would drop pieces the app still wants to draw.
const APP_SCREEN_RESOLUTION = 100;
// Output coordinate precision (decimal digits) per LOD. 4 digits is about 11 m and 5 digits about 1 m, far below
// the simplification interval (2 km / 500 m), so nothing visible changes while the files get smaller.
// Mapshaper writes 6 digits everywhere; pruneAndRound rounds after the small islands are gone.
const COORDINATE_DIGITS = { 0: 4, 1: 5, 2: 6, 3: 6 };
function coordinateDigits(lod) {
  const digits = COORDINATE_DIGITS[lod];
  ensure(digits !== undefined, `Unknown LOD: ${lod}`);
  return digits;
}
/** Pieces smaller than this can never be drawn at this LOD: the screen is at least `zoomInBelowMeters` wide
 * before the app switches to the finer LOD. The finest LOD can be zoomed without limit, so it keeps everything. */
function minimumPieceMeters(lod) {
  const transition = LOD_TRANSITIONS.find(t => t.coarseLOD === lod);
  return transition ? transition.zoomInBelowMeters / APP_SCREEN_RESOLUTION : 0;
}
// Layer directory -> file prefix, property holding the feature key, and split unit for LOD 1-3.
const LAYERS = {
  municipalities: { prefix: 'municipality', key: 'c', split: 'prefecture' },
  prefectures: { prefix: 'prefecture', key: 'p', split: 'prefecture' },
  regions: { prefix: 'region', key: 'r', split: 'region' },
  // Prefecture borders and coastlines as lines (see prefectureLines). Each file holds the lines OWNED by
  // one prefecture, so a file does not cover every border of that prefecture and codes are not unique.
  prefectureLines: { prefix: 'prefecture_line', key: 'p', split: 'prefecture', geometry: 'line' },
};
const LINE_KINDS = new Set(['coast', 'border']);
const PREFS = Array.from({ length: 47 }, (_, i) => String(i + 1).padStart(2, '0'));
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const write = (p, value) => fs.writeFileSync(p, JSON.stringify(value, null, 2) + '\n');
const text = v => v == null ? '' : String(v).trim();
const equalSets = (a, b) => a.size === b.size && [...a].every(x => b.has(x));
function ensure(ok, message) { if (!ok) throw new Error(message); }
function goodBBox(b) {
  return Array.isArray(b) && b.length === 4 && b.every(Number.isFinite) &&
    b[0] >= -180 && b[2] <= 180 && b[1] >= -90 && b[3] <= 90 &&
    b[0] <= b[2] && b[1] <= b[3];
}

/** Validate regions.json: two-digit unique codes, names, and every prefecture in exactly one region. */
function loadRegions(file) {
  const def = read(file);
  const regions = def.regions;
  ensure(Array.isArray(regions) && regions.length > 0, `${file}: "regions" must be a nonempty array.`);
  const codes = new Set(), assigned = new Map();
  for (const r of regions) {
    ensure(/^\d{2}$/.test(r.code || ''), `${file}: invalid region code ${r.code}`);
    ensure(!codes.has(r.code), `${file}: duplicate region code ${r.code}`);
    ensure(text(r.name) && text(r.nameEn), `${file}: region ${r.code} needs name and nameEn.`);
    ensure(Array.isArray(r.prefectureCodes) && r.prefectureCodes.length > 0, `${file}: region ${r.code} has no prefectures.`);
    codes.add(r.code);
    for (const p of r.prefectureCodes) {
      ensure(PREFS.includes(p), `${file}: unknown prefecture code ${p}`);
      ensure(!assigned.has(p), `${file}: prefecture ${p} belongs to both ${assigned.get(p)} and ${r.code}`);
      assigned.set(p, r.code);
    }
  }
  ensure(assigned.size === PREFS.length, `${file}: prefectures without a region: ${PREFS.filter(p => !assigned.has(p)).join(',')}`);
  return { def, regions, regionOfPref: Object.fromEntries(assigned) };
}

function audit(input, regionsFile, report) {
  const { def, regions, regionOfPref } = loadRegions(regionsFile);
  const rows = read(input);
  ensure(Array.isArray(rows) && rows.length > 0, 'Attribute export must be a nonempty JSON array.');
  const fields = new Set(rows.flatMap(r => Object.keys(r || {})));
  const errors = [];
  for (const key of ['N03_001', 'N03_004', 'N03_005', 'N03_007']) {
    if (!fields.has(key)) errors.push({ issue: `Missing 2026 schema field: ${key}` });
  }
  const codes = new Map(), prefNames = new Map();
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i] || {};
    const c = typeof r.N03_007 === 'string' ? r.N03_007.trim() : '';
    const p = c.slice(0, 2), pn = text(r.N03_001);
    const n = text(r.N03_004) + text(r.N03_005);
    if (!/^\d{5}$/.test(c) || !PREFS.includes(p) || !pn || !text(r.N03_004)) {
      errors.push({ row: i, issue: 'Invalid/missing code, prefecture or municipality name', properties: r });
      continue;
    }
    if (codes.has(c) && (codes.get(c).n !== n || codes.get(c).p !== p)) {
      errors.push({ row: i, issue: 'Conflicting names for a municipality code', properties: r });
    }
    if (prefNames.has(p) && prefNames.get(p) !== pn) {
      errors.push({ row: i, issue: 'Conflicting prefecture names for a code', properties: r });
    }
    codes.set(c, { c, n, p, r: regionOfPref[p] });
    prefNames.set(p, pn);
  }
  if (!equalSets(new Set(prefNames.keys()), new Set(PREFS))) {
    errors.push({ issue: 'Expected all 47 prefecture codes', found: [...prefNames.keys()].sort() });
  }
  write(report, {
    sourceSchema: 'N03-2026', sourceFeatureCount: rows.length,
    municipalityCount: codes.size,
    municipalities: [...codes.values()].sort((a, b) => a.c.localeCompare(b.c)),
    prefectures: [...prefNames].sort().map(([p, n]) => ({ p, n, r: regionOfPref[p] })),
    regions, regionSource: def.source, errors,
  });
  ensure(!errors.length, `${errors.length} source issues. See ${report}. No records were silently discarded.`);
  console.log(`Source audit: ${codes.size} municipality codes; ${prefNames.size} prefectures; ${regions.length} regions.`);
}

/** Print a Mapshaper -each expression. Values are JSON-encoded, so names are safely quoted. */
function regionExpr(regionsFile) {
  const { regionOfPref } = loadRegions(regionsFile);
  console.log(`r=(${JSON.stringify(regionOfPref)})[p]`);
}
function regionNameExpr(regionsFile) {
  const { regions } = loadRegions(regionsFile);
  console.log(`n=(${JSON.stringify(Object.fromEntries(regions.map(r => [r.code, r.name])))})[r]`);
}

function baseline(input, sourceReport, report) {
  const rows = read(input), source = read(sourceReport);
  const regionOfPref = Object.fromEntries(source.prefectures.map(x => [x.p, x.r]));
  const counts = {}, seen = new Set(), errors = [];
  for (const r of rows) {
    if (r._null || !goodBBox(r._bbox)) {
      errors.push({ c: r.c, issue: 'Empty shape or invalid longitude/latitude bounds', bbox: r._bbox });
    }
    if (r.r !== regionOfPref[r.p]) errors.push({ c: r.c, issue: 'Missing or wrong region code', r: r.r });
    counts[r.c] = (counts[r.c] || 0) + 1;
    seen.add(r.c);
  }
  if (!equalSets(seen, new Set(source.municipalities.map(r => r.c)))) {
    errors.push({ issue: 'Municipality code set changed during normalization' });
  }
  write(report, { partCountByCode: counts, explodedFeatureCount: rows.length, errors });
  ensure(!errors.length, `Normalization issues. See ${report}.`);
}

function geometryStats(g, label) {
  ensure(g && ['Polygon', 'MultiPolygon'].includes(g.type), `${label}: expected Polygon/MultiPolygon.`);
  const polys = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
  ensure(Array.isArray(polys) && polys.length > 0, `${label}: empty geometry.`);
  const bbox = [Infinity, Infinity, -Infinity, -Infinity];
  let vertexCount = 0, holeCount = 0;
  for (const poly of polys) {
    ensure(Array.isArray(poly) && poly.length > 0, `${label}: empty polygon.`);
    holeCount += poly.length - 1;
    for (const ring of poly) {
      ensure(Array.isArray(ring) && ring.length >= 4, `${label}: ring has fewer than four positions.`);
      const first = ring[0], last = ring[ring.length - 1];
      ensure(first[0] === last[0] && first[1] === last[1], `${label}: unclosed ring.`);
      const unique = new Set();
      let area2 = 0;
      for (let i = 0; i < ring.length; i++) {
        const v = ring[i];
        ensure(Array.isArray(v) && v.length === 2 && v.every(Number.isFinite), `${label}: invalid 2D position.`);
        const [x, y] = v;
        ensure(x >= -180 && x <= 180 && y >= -90 && y <= 90, `${label}: not longitude/latitude.`);
        bbox[0] = Math.min(bbox[0], x); bbox[1] = Math.min(bbox[1], y);
        bbox[2] = Math.max(bbox[2], x); bbox[3] = Math.max(bbox[3], y);
        unique.add(`${x},${y}`);
        if (i > 0) {
          const prev = ring[i - 1];
          area2 += (prev[0] - first[0]) * (y - first[1]) - (x - first[0]) * (prev[1] - first[1]);
        }
        vertexCount++;
      }
      ensure(unique.size >= 3 && area2 !== 0, `${label}: degenerate ring after simplification/rounding.`);
    }
  }
  return { bbox, polygonCount: polys.length, holeCount, vertexCount };
}
function lineStats(g, label) {
  ensure(g && ['LineString', 'MultiLineString'].includes(g.type), `${label}: expected LineString/MultiLineString.`);
  const lines = g.type === 'LineString' ? [g.coordinates] : g.coordinates;
  ensure(Array.isArray(lines) && lines.length > 0, `${label}: empty geometry.`);
  const bbox = [Infinity, Infinity, -Infinity, -Infinity];
  let vertexCount = 0;
  for (const line of lines) {
    ensure(Array.isArray(line) && line.length >= 2, `${label}: line has fewer than two positions.`);
    for (const v of line) {
      ensure(Array.isArray(v) && v.length === 2 && v.every(Number.isFinite), `${label}: invalid 2D position.`);
      const [x, y] = v;
      ensure(x >= -180 && x <= 180 && y >= -90 && y <= 90, `${label}: not longitude/latitude.`);
      bbox[0] = Math.min(bbox[0], x); bbox[1] = Math.min(bbox[1], y);
      bbox[2] = Math.max(bbox[2], x); bbox[3] = Math.max(bbox[3], y);
      vertexCount++;
    }
  }
  return { bbox, lineCount: lines.length, vertexCount };
}
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : p.endsWith('.geojson') ? [p] : [];
  }).sort();
}
function manifest(root, sourceReport, baselineReport, report, versionFile) {
  const source = read(sourceReport), base = read(baselineReport);
  const regionOfPref = Object.fromEntries(source.prefectures.map(x => [x.p, x.r]));
  const expected = {
    municipalities: new Set(source.municipalities.map(r => r.c)),
    prefectures: new Set(source.prefectures.map(r => r.p)),
    regions: new Set(source.regions.map(r => r.code)),
  };
  const seen = Object.fromEntries(LODS.flatMap(l => Object.keys(LAYERS).map(layer => [`${layer}:${l.id}`, new Set()])));
  const files = [], errors = [], warnings = [];
  for (const file of walk(root)) {
    const rel = path.relative(root, file).split(path.sep).join('/');
    try {
      const m = rel.match(/^(municipalities|prefectures|regions|prefectureLines)\/lod([0-3])_(\d+)m\/(municipality|prefecture|region|prefecture_line)_(jp|\d{2})_lod([0-3])\.geojson$/);
      ensure(m, `Unexpected output filename: ${rel}`);
      const layer = m[1], lod = Number(m[2]), spec = LAYERS[layer];
      const scope = m[5] === 'jp' ? null : m[5];
      ensure(Number(m[3]) === LODS[lod].intervalMeters && Number(m[6]) === lod && m[4] === spec.prefix, `LOD/name mismatch: ${rel}`);
      ensure((lod === 0) === (scope === null), `Unexpected split scope: ${rel}`);
      const pref = spec.split === 'prefecture' ? scope : null;
      const region = spec.split === 'region' ? scope : (pref ? regionOfPref[pref] : null);
      ensure(scope === null || (pref ? expected.prefectures.has(pref) : expected.regions.has(region)), `Unknown split code: ${rel}`);
      const bytes = fs.readFileSync(file), data = JSON.parse(bytes.toString('utf8'));
      ensure(data.type === 'FeatureCollection' && Array.isArray(data.features) && data.features.length > 0, `${rel}: empty/non-FeatureCollection.`);
      const bbox = [Infinity, Infinity, -Infinity, -Infinity];
      let polygonCount = 0, holeCount = 0, vertexCount = 0, lineCount = 0;
      if (spec.geometry === 'line') {
        for (const f of data.features) {
          ensure(f.type === 'Feature', `${rel}: not a Feature.`);
          const a = f.properties || {};
          ensure(LINE_KINDS.has(a.k), `${rel}: invalid line kind ${a.k}.`);
          ensure(pref === null ? a.p === undefined : a.p === pref, `${rel}: line owned by a different prefecture.`);
          const s = lineStats(f.geometry, `${rel}/${a.k}`);
          for (let i = 0; i < 2; i++) { bbox[i] = Math.min(bbox[i], s.bbox[i]); bbox[i + 2] = Math.max(bbox[i + 2], s.bbox[i + 2]); }
          lineCount += s.lineCount; vertexCount += s.vertexCount;
        }
        files.push({ id: `${spec.prefix}_${scope || 'jp'}_lod${lod}`, layer, lod,
          prefectureCode: pref, regionCode: region,
          path: rel, bbox, byteSize: bytes.length, featureCount: data.features.length,
          lineCount, vertexCount,
          sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
        continue;
      }
      for (const f of data.features) {
        ensure(f.type === 'Feature', `${rel}: not a Feature.`);
        const a = f.properties || {}, key = a[spec.key];
        ensure(expected[layer].has(key), `${rel}: unknown code ${key}`);
        ensure(typeof a.n === 'string' && a.n.length > 0, `${rel}: missing name.`);
        ensure(typeof a.r === 'string' && expected.regions.has(a.r), `${rel}: invalid region code.`);
        if (layer !== 'regions') {
          ensure(typeof a.p === 'string' && expected.prefectures.has(a.p), `${rel}: invalid prefecture code.`);
          ensure(a.r === regionOfPref[a.p], `${rel}: ${key} has region ${a.r}, expected ${regionOfPref[a.p]}.`);
          ensure(pref === null || a.p === pref, `${rel}: feature belongs to a different prefecture.`);
        } else {
          ensure(region === null || a.r === region, `${rel}: feature belongs to a different region.`);
        }
        ensure(layer !== 'municipalities' || a.c.slice(0, 2) === a.p, `${rel}: municipality/prefecture mismatch.`);
        const bucket = seen[`${layer}:${lod}`];
        ensure(!bucket.has(key), `${rel}: duplicate Feature for ${key}.`);
        bucket.add(key);
        const s = geometryStats(f.geometry, `${rel}/${key}`);
        for (let i = 0; i < 2; i++) { bbox[i] = Math.min(bbox[i], s.bbox[i]); bbox[i + 2] = Math.max(bbox[i + 2], s.bbox[i + 2]); }
        polygonCount += s.polygonCount; holeCount += s.holeCount; vertexCount += s.vertexCount;
        // Pruned LODs drop small islands on purpose (pruneAndRound), so only unpruned LODs are compared.
        if (layer === 'municipalities' && minimumPieceMeters(lod) === 0 && s.polygonCount !== base.partCountByCode[key]) {
          warnings.push({ file: rel, c: key, issue: 'Outer component count changed; inspect visually', before: base.partCountByCode[key], after: s.polygonCount });
        }
      }
      files.push({ id: `${spec.prefix}_${scope || 'jp'}_lod${lod}`, layer, lod,
        prefectureCode: pref, regionCode: region,
        path: rel, bbox, byteSize: bytes.length, featureCount: data.features.length,
        polygonCount, holeCount, vertexCount,
        sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
    } catch (err) { errors.push({ file: rel, issue: err.message }); }
  }
  for (const l of LODS) {
    for (const [layer, spec] of Object.entries(LAYERS)) {
      const count = files.filter(f => f.layer === layer && f.lod === l.id).length;
      if (spec.geometry === 'line') {
        // A prefecture whose every border is owned by lower-coded neighbours can have no file.
        if (l.id === 0 ? count !== 1 : count < 1 || count > expected.prefectures.size) {
          errors.push({ issue: `File count mismatch: ${layer}, LOD ${l.id}`, count });
        }
        continue;
      }
      if (!equalSets(seen[`${layer}:${l.id}`], expected[layer])) errors.push({ issue: `Code coverage mismatch: ${layer}, LOD ${l.id}` });
      const splitCount = spec.split === 'region' ? expected.regions.size : expected.prefectures.size;
      if (count !== (l.id === 0 ? 1 : splitCount)) errors.push({ issue: `File count mismatch: ${layer}, LOD ${l.id}`, count });
    }
  }
  write(report, { generatedGeoJSONFiles: files.length, totalBytes: files.reduce((n, f) => n + f.byteSize, 0),
    errors, warnings, spatialTopologyValidation: 'NOT_PERFORMED',
    remainingChecks: ['Shared boundaries, overlaps and gaps', 'Hole preservation and small islands', 'iPhone rendering and memory', 'Source attribution and distribution requirements'] });
  ensure(errors.length === 0, `Output checks failed. See ${report}.`);
  write(path.join(root, 'manifest.json'), {
    schemaVersion: 2, dataVersion: '20260101', buildRevision: 4,
    builtAt: new Date().toISOString(),
    generator: { name: 'mapshaper', version: fs.readFileSync(versionFile, 'utf8').trim() },
    releaseStatus: 'needs_spatial_and_device_review',
    coordinateSystem: 'longitude-latitude/WGS84',
    lods: LODS.map(l => ({ ...l, method: 'dp', split: l.id === 0 ? 'national' : 'prefecture/region',
      minPieceMeters: minimumPieceMeters(l.id), coordinateDigits: coordinateDigits(l.id) })),
    lodTransitions: LOD_TRANSITIONS,
    source: { name: 'MLIT National Land Numerical Information N03', date: '2026-01-01',
      url: 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-2026.html' },
    regionSource: source.regionSource,
    regions: source.regions,
    files,
  });
  const attribution = [
    '出典: 国土交通省「国土数値情報 行政区域データ（N03）」',
    'データ基準日: 2026年1月1日',
    'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-2026.html',
    'ライセンス: CC BY 4.0',
    'https://creativecommons.org/licenses/by/4.0/',
    '加工: 属性整理、境界のすき間・重なりの修復、同一コードの形状統合、境界簡略化、都道府県別分割、都道府県外形・県境線および地方外形の生成。',
    '地方区分: 国土地理院「日本の典型地形」の地域別リストに準拠。',
    '境界は概略表示であり、測量等の精密な用途には使用しないでください。',
  ];
  fs.writeFileSync(path.join(root, 'attribution.txt'), attribution.join('\n') + '\n');
  console.log(`Manifest: ${files.length} GeoJSON files; ${warnings.length} component-count warnings. See ${report}.`);
}
/** Split the national prefecture line layer (Mapshaper `-lines p`, RANK < 2) into per-prefecture files.
 *
 * Each line is owned by exactly ONE prefecture so that a shared border is drawn once:
 * the lower code of the two prefectures it separates, or the only prefecture for a coastline.
 * Ownership is found by exact vertex matching against the prefecture polygons of the SAME LOD
 * (same simplified topology and output precision, so coordinates are identical).
 * Lines with the same owner and kind are then chained end to end: the app draws one overlay
 * per line, so fewer, longer lines are much cheaper to render.
 */
function prefectureLines(linesFile, prefectureDir, outDir, lodText) {
  const lod = Number(lodText);
  ensure(LODS.some(l => l.id === lod), `Unknown LOD: ${lodText}`);
  const key = ([x, y]) => `${x},${y}`;

  const prefsOfVertex = new Map();
  for (const file of walk(prefectureDir)) {
    for (const f of read(file).features) {
      const polys = f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates;
      for (const ring of polys.flat()) {
        for (const v of ring) {
          const k = key(v);
          if (!prefsOfVertex.has(k)) prefsOfVertex.set(k, new Set());
          prefsOfVertex.get(k).add(f.properties.p);
        }
      }
    }
  }

  // Explode MultiLineStrings and assign owner + kind to each part.
  const parts = [];
  const errors = [];
  for (const f of read(linesFile).features) {
    const kind = f.properties.TYPE === 'outer' ? 'coast' : 'border';
    const lines = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.coordinates;
    for (const line of lines) {
      let common = null;
      for (const v of line) {
        const prefs = prefsOfVertex.get(key(v)) || new Set();
        common = common === null ? new Set(prefs) : new Set([...common].filter(p => prefs.has(p)));
      }
      // Normally a coastline has 1 prefecture in common and a border has 2. A very short line whose
      // vertices are all junctions (e.g. where a border reaches the coast of a shared island) can have
      // more; the lowest code still gives a stable single owner, so only "no prefecture" is an error.
      if (!common || common.size === 0) {
        errors.push({ kind, first: line[0], prefectures: common ? [...common] : [] });
        continue;
      }
      parts.push({ owner: [...common].sort()[0], kind, coords: line });
    }
  }
  ensure(errors.length === 0, `${errors.length} lines could not be assigned to prefectures (LOD ${lod}). First: ${JSON.stringify(errors[0])}`);

  const groups = new Map();
  for (const part of parts) {
    const groupKey = lod === 0 ? `jp|${part.kind}` : `${part.owner}|${part.kind}`;
    if (!groups.has(groupKey)) groups.set(groupKey, []);
    groups.get(groupKey).push(part);
  }

  // One Feature per owner and kind (MultiLineString). Most lines are tiny island coastlines, and
  // repeating properties on each of ~120k Features would roughly double the file size.
  const featuresByFile = new Map();
  let chainedCount = 0;
  for (const [groupKey, group] of groups) {
    const [scope, kind] = groupKey.split('|');
    const chains = chainLines(group.map(p => p.coords), key);
    chainedCount += chains.length;
    if (!featuresByFile.has(scope)) featuresByFile.set(scope, []);
    featuresByFile.get(scope).push({
      type: 'Feature', properties: lod === 0 ? { k: kind } : { p: scope, k: kind },
      geometry: { type: 'MultiLineString', coordinates: chains },
    });
  }

  const interval = LODS[lod].intervalMeters;
  const dir = path.join(outDir, `lod${lod}_${interval}m`);
  fs.mkdirSync(dir, { recursive: true });
  for (const [scope, features] of featuresByFile) {
    const bbox = [Infinity, Infinity, -Infinity, -Infinity];
    for (const f of features) {
      for (const [x, y] of f.geometry.coordinates.flat()) {
        bbox[0] = Math.min(bbox[0], x); bbox[1] = Math.min(bbox[1], y);
        bbox[2] = Math.max(bbox[2], x); bbox[3] = Math.max(bbox[3], y);
      }
    }
    fs.writeFileSync(path.join(dir, `prefecture_line_${scope}_lod${lod}.geojson`),
      JSON.stringify({ type: 'FeatureCollection', bbox, features }));
  }
  console.log(`Prefecture lines LOD ${lod}: ${parts.length} parts -> ${chainedCount} chained lines in ${featuresByFile.size} files.`);
}

/** Join lines that meet end to end at a node used by exactly two line ends. Closed rings stay as they are. */
function chainLines(lines, key) {
  const endsAt = new Map();
  const addEnd = (k, i) => { if (!endsAt.has(k)) endsAt.set(k, []); endsAt.get(k).push(i); };
  lines.forEach((line, i) => {
    const a = key(line[0]), b = key(line[line.length - 1]);
    if (a === b) return;
    addEnd(a, i); addEnd(b, i);
  });
  const used = new Array(lines.length).fill(false);
  // Only continue through a node where exactly two line ends meet; at a junction of three or more
  // (e.g. where three prefectures meet) the chain stops.
  const partnerAt = k => {
    const ids = endsAt.get(k) || [];
    return ids.length === 2 ? ids.find(j => !used[j]) : undefined;
  };
  const result = [];
  for (let start = 0; start < lines.length; start++) {
    if (used[start]) continue;
    used[start] = true;
    let chain = lines[start].slice();
    if (key(chain[0]) === key(chain[chain.length - 1])) { result.push(chain); continue; }
    // Extend forward, then backward.
    for (const forward of [true, false]) {
      for (;;) {
        const isClosed = key(chain[0]) === key(chain[chain.length - 1]);
        const endKey = key(forward ? chain[chain.length - 1] : chain[0]);
        const j = partnerAt(endKey);
        if (isClosed || j === undefined) break;
        used[j] = true;
        let next = lines[j];
        if (forward) {
          if (key(next[0]) !== endKey) next = next.slice().reverse();
          chain = chain.concat(next.slice(1));
        } else {
          if (key(next[next.length - 1]) !== endKey) next = next.slice().reverse();
          chain = next.slice(0, -1).concat(chain);
        }
      }
    }
    result.push(chain);
  }
  return result;
}

/** Make one LOD as light as the app allows: drop the pieces it can never draw there, then round coordinates.
 *
 * keep-shapes keeps every one of the ~125k islands, so without this LOD0 was 12 MB per layer and ~96% of
 * its vertices were islands of 10 vertices or fewer. The app decoded them only to throw them away
 * (BoundaryPieceFilter), which made the first map load take seconds on an iPhone.
 * The pruning rule is the app's own rule (see minimumPieceMeters), so what is drawn does not change:
 *   - polygons: keep the largest piece of each feature, and every piece whose bbox is at least the minimum.
 *   - lines: drop only closed lines (small island coasts) below the minimum. Open lines can be one segment
 *     of a long border, and dropping them would leave gaps.
 * Rounding (COORDINATE_DIGITS) comes after pruning, so only large pieces are rounded. Identical input
 * coordinates round identically, so shared borders and lines still coincide. Repeated points are removed,
 * and a hole that collapses is dropped (it was far below one screen point at this LOD).
 * Run after prefecture-lines, which needs every prefecture vertex at full precision to assign line owners.
 */
function pruneAndRound(root, lodText) {
  const lod = Number(lodText);
  const minimum = minimumPieceMeters(lod);
  const digits = coordinateDigits(lod);
  if (minimum === 0 && digits === 6) {
    console.log(`Prune/round LOD ${lod}: finest LOD, output kept as is.`);
    return;
  }
  const roundPath = positions => {
    const rounded = [];
    for (const [x, y] of positions) {
      const v = [Number(x.toFixed(digits)), Number(y.toFixed(digits))];
      const prev = rounded[rounded.length - 1];
      if (!prev || prev[0] !== v[0] || prev[1] !== v[1]) rounded.push(v);
    }
    return rounded;
  };
  const dirName = `lod${lod}_${LODS[lod].intervalMeters}m`;
  let before = 0, after = 0, droppedHoles = 0;
  for (const [layer, spec] of Object.entries(LAYERS)) {
    const dir = path.join(root, layer, dirName);
    if (!fs.existsSync(dir)) continue;
    for (const file of walk(dir)) {
      const data = read(file);
      const features = [];
      for (const f of data.features) {
        const g = f.geometry;
        if (spec.geometry === 'line') {
          const lines = g.type === 'LineString' ? [g.coordinates] : g.coordinates;
          const kept = lines
            .filter(line => !isClosedLine(line) || longerSideMeters(line) >= minimum)
            .map(roundPath)
            .filter(line => line.length >= 2);
          before += lines.length; after += kept.length;
          if (kept.length) features.push({ ...f, geometry: { type: 'MultiLineString', coordinates: kept } });
          continue;
        }
        const polys = g.type === 'Polygon' ? [g.coordinates] : g.coordinates;
        const sizes = polys.map(poly => longerSideMeters(poly[0]));
        const largest = sizes.indexOf(Math.max(...sizes));
        const kept = polys
          .filter((_, i) => i === largest || sizes[i] >= minimum)
          .map(([exterior, ...holes]) => {
            const roundedExterior = roundPath(exterior);
            ensure(isValidRing(roundedExterior), `${file}: a kept piece collapsed when rounded to ${digits} digits.`);
            const roundedHoles = holes.map(roundPath).filter(isValidRing);
            droppedHoles += holes.length - roundedHoles.length;
            return [roundedExterior, ...roundedHoles];
          });
        before += polys.length; after += kept.length;
        features.push({ ...f, geometry: kept.length === 1
          ? { type: 'Polygon', coordinates: kept[0] }
          : { type: 'MultiPolygon', coordinates: kept } });
      }
      // A line file can lose every line (an owner of nothing but small island coasts). The app does not need it.
      if (!features.length) { fs.rmSync(file); continue; }
      fs.writeFileSync(file, JSON.stringify({ type: 'FeatureCollection', bbox: featuresBBox(features), features }));
    }
  }
  console.log(`Prune/round LOD ${lod}: pieces smaller than ${minimum} m removed (${before} -> ${after}); ` +
    `${digits} digits; ${droppedHoles} collapsed holes dropped.`);
}
/** A closed ring with at least 3 distinct points and nonzero area (the same test as geometryStats). */
function isValidRing(ring) {
  if (ring.length < 4) return false;
  const first = ring[0], last = ring[ring.length - 1];
  if (first[0] !== last[0] || first[1] !== last[1]) return false;
  if (new Set(ring.map(([x, y]) => `${x},${y}`)).size < 3) return false;
  let area2 = 0;
  for (let i = 1; i < ring.length; i++) {
    const prev = ring[i - 1], v = ring[i];
    area2 += (prev[0] - first[0]) * (v[1] - first[1]) - (v[0] - first[0]) * (prev[1] - first[1]);
  }
  return area2 !== 0;
}
function isClosedLine(line) {
  const first = line[0], last = line[line.length - 1];
  return line.length > 2 && first[0] === last[0] && first[1] === last[1];
}
/** Same as GeoBoundingBox.longerSideMeters in the app, so both sides agree on what is "too small". */
function longerSideMeters(positions) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of positions) {
    minX = Math.min(minX, x); minY = Math.min(minY, y);
    maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
  }
  const metersPerDegreeLongitude = 111320 * Math.cos(((minY + maxY) / 2) * Math.PI / 180);
  return Math.max((maxX - minX) * metersPerDegreeLongitude, (maxY - minY) * 110540);
}
function featuresBBox(features) {
  const bbox = [Infinity, Infinity, -Infinity, -Infinity];
  for (const f of features) {
    const g = f.geometry;
    const rings = g.type === 'MultiPolygon' ? g.coordinates.flat() : g.coordinates;
    for (const [x, y] of rings.flat()) {
      bbox[0] = Math.min(bbox[0], x); bbox[1] = Math.min(bbox[1], y);
      bbox[2] = Math.max(bbox[2], x); bbox[3] = Math.max(bbox[3], y);
    }
  }
  return bbox;
}

async function hash(input, report) {
  const h = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(input)) h.update(chunk);
  write(report, { sourceFile: path.basename(input), byteSize: fs.statSync(input).size, sha256: h.digest('hex') });
}
const [command, ...args] = process.argv.slice(2);
try {
  if (command === 'audit') audit(...args);
  else if (command === 'region-expr') regionExpr(...args);
  else if (command === 'region-name-expr') regionNameExpr(...args);
  else if (command === 'baseline') baseline(...args);
  else if (command === 'manifest') manifest(...args);
  else if (command === 'prefecture-lines') prefectureLines(...args);
  else if (command === 'prune-and-round') pruneAndRound(...args);
  else if (command === 'hash') await hash(...args);
  else throw new Error('Use audit, region-expr, region-name-expr, baseline, prefecture-lines, prune-and-round, manifest, or hash. See build_boundaries.sh for arguments.');
} catch (err) { console.error(`ERROR: ${err.message}`); process.exitCode = 1; }
