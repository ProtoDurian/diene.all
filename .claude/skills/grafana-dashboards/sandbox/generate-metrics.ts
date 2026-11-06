// Synthetic OpenMetrics for promtool backfill; rename the metrics and labels to match your dashboard.
const counter = 'sample_requests';
const histogram = 'sample_request_duration_seconds';
const identity = 'platform="sandbox",service="sample",module="api"';
const landscapes = { pichu: 300, raichu: 70 };
const buckets = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5];
const step = 30;
const hours = 6;

const end = Math.floor(Date.now() / 1000 / step) * step;
const start = end - hours * 3600;
const counters: string[] = [];
const histograms: string[] = [];

for (const [landscape, baseRate] of Object.entries(landscapes)) {
  const labels = `landscape="${landscape}",${identity}`;
  let ok = 0;
  let failed = 0;
  let count = 0;
  let sum = 0;
  const below = buckets.map(() => 0);
  for (let t = start, i = 0; t <= end; t += step, i++) {
    const incident = i > 280 && i < 390;
    const requests = baseRate + Math.round(120 * ((Math.sin(i / 19) + 1) / 2));
    const errors = Math.round(requests * (incident ? 0.09 : 0.004));
    const mean = incident ? 0.35 : 0.07;
    ok += requests - errors;
    failed += errors;
    count += requests;
    sum += requests * mean;
    counters.push(`${counter}_total{${labels},outcome="success"} ${ok} ${t}`);
    counters.push(`${counter}_total{${labels},outcome="error"} ${failed} ${t}`);
    buckets.forEach((le, j) => {
      below[j] += Math.round(requests * (1 - Math.exp(-le / mean)));
      histograms.push(`${histogram}_bucket{${labels},le="${le}"} ${below[j]} ${t}`);
    });
    histograms.push(`${histogram}_bucket{${labels},le="+Inf"} ${count} ${t}`);
    histograms.push(`${histogram}_count{${labels}} ${count} ${t}`);
    histograms.push(`${histogram}_sum{${labels}} ${sum.toFixed(3)} ${t}`);
  }
}

const sortBySeries = (lines: string[]) =>
  lines
    .map((line, order) => ({ line, order, series: line.slice(0, line.lastIndexOf('} ') + 1) }))
    .sort((a, b) => (a.series === b.series ? a.order - b.order : a.series < b.series ? -1 : 1))
    .map(({ line }) => line);

const output = [
  `# TYPE ${counter} counter`,
  ...sortBySeries(counters),
  `# TYPE ${histogram} histogram`,
  ...sortBySeries(histograms),
  '# EOF',
];
console.log(output.join('\n'));
