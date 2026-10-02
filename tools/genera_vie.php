<?php
/**
 * Rigenera assets/corbetta_streets.json: l'elenco delle vie di Corbetta
 * preso da OpenStreetMap, con un punto (lat, lon) per ognuna.
 *
 * Serve all'app per trovare le vie anche quando il nome scritto non e'
 * identico a quello di OSM ("Via Ghiaccio" → "Vicolo del Ghiaccio").
 * Da rilanciare quando su OSM vengono aggiunte o rinominate vie:
 *
 *   php tools/genera_vie.php
 */

$root = dirname(__DIR__);
$polygon = json_decode(file_get_contents($root.'/assets/corbetta_boundary.json'), true);

// Area OSM = 3600000000 + id della relazione del Comune (45011).
$query = '[out:json][timeout:90];area(3600045011)->.a;('
    .'way(area.a)[highway][name];'
    .'way(area.a)[place=square][name];'
    .');out tags geom;';

$ctx = stream_context_create(['http' => [
    'method' => 'POST',
    'header' => "User-Agent: castellazzodestampi-app/1.0\r\nContent-Type: application/x-www-form-urlencoded\r\n",
    'content' => http_build_query(['data' => $query]),
    'timeout' => 120,
]]);
$raw = file_get_contents('https://overpass-api.de/api/interpreter', false, $ctx);
if (!$raw) {
    fwrite(STDERR, "Overpass non risponde, riprova piu' tardi.\n");
    exit(1);
}

function inside(array $p, float $lat, float $lon): bool
{
    $in = false;
    $n = count($p);
    for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
        [$latI, $lonI] = $p[$i];
        [$latJ, $lonJ] = $p[$j];
        if (($latI > $lat) !== ($latJ > $lat)
            && $lon < ($lonJ - $lonI) * ($lat - $latI) / ($latJ - $latI) + $lonI) {
            $in = !$in;
        }
    }
    return $in;
}

// Una via e' spesso spezzata in piu' tratti, e quelle di confine stanno
// solo in parte a Corbetta: si raccolgono i punti del tracciato che cadono
// dentro il confine.
$byName = [];
foreach (json_decode($raw, true)['elements'] ?? [] as $el) {
    $name = trim($el['tags']['name'] ?? '');
    if ($name === '') {
        continue;
    }
    foreach ($el['geometry'] ?? [] as $c) {
        if (inside($polygon, $c['lat'], $c['lon'])) {
            $byName[$name][] = [$c['lat'], $c['lon']];
        }
    }
}

// Per ogni via si tiene il punto del tracciato piu' vicino alla media:
// sta davvero sulla via, a meta' circa del tratto di Corbetta.
$streets = [];
foreach ($byName as $name => $points) {
    $mLat = array_sum(array_column($points, 0)) / count($points);
    $mLon = array_sum(array_column($points, 1)) / count($points);
    usort($points, fn ($a, $b) => (($a[0] - $mLat) ** 2 + ($a[1] - $mLon) ** 2)
        <=> (($b[0] - $mLat) ** 2 + ($b[1] - $mLon) ** 2));
    $streets[] = ['name' => $name, 'lat' => round($points[0][0], 7), 'lon' => round($points[0][1], 7)];
}
usort($streets, fn ($a, $b) => strcmp($a['name'], $b['name']));

file_put_contents(
    $root.'/assets/corbetta_streets.json',
    json_encode($streets, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)."\n"
);
echo count($streets)." vie salvate in assets/corbetta_streets.json\n";
