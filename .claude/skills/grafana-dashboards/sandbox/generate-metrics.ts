// Synthetic OpenMetrics for promtool backfill. Edit the config block to match your dashboard's queries.
const config = {
  identity: 'platform="sandbox",service="sample",module="api"',
  landscapes: { pichu: 300, raichu: 70 },
  counter: 'sample_requests',
  successOutcome: 'success',
  failureOutcomes: { error: 0.004 },
  incident: { outcome: 'error', share: 0.09 },
  histogram: 'sample_request_duration_seconds',
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  gauge: 'sample_queue_depth',
  step: 30,
  hours: 6,
};

const { step } = config;
const end = Math.floor(Date.now() / 1000 / step) * step;
const start = end - config.hours * 3600;
const counters: string[] = [];
const histograms: string[] = [];
const gauges: string[] = [];

for (const [landscape, baseRate] of Object.entries(config.landscapes)) {
  const labels = `landscape="${landscape}",${config.identity}`;
  const totals: Record<string, number> = { [config.successOutcome]: 0 };
  let count = 0;
  let sum = 0;
  const below = config.buckets.map(() => 0);
  for (let t = start, i = 0; t <= end; t += step, i++) {
    const incident = i > 280 && i < 390;
    const requests = baseRate + Math.round(120 * ((Math.sin(i / 19) + 1) / 2));
    const mean = incident ? 0.35 : 0.07;
    let succeeded = requests;
    for (const [outcome, normal] of Object.entries(config.failureOutcomes)) {
      const share = incident && outcome === config.incident.outcome ? config.incident.share : normal;
      const failed = Math.round(requests * share);
      totals[outcome] = (totals[outcome] ?? 0) + failed;
      succeeded -= failed;
    }
    totals[config.successOutcome] += succeeded;
    for (const [outcome, total] of Object.entries(totals)) {
      counters.push(`${config.counter}_total{${labels},outcome="${outcome}"} ${total} ${t}`);
    }
    count += requests;
    sum += requests * mean;
    config.buckets.forEach((le, j) => {
      below[j] += Math.round(requests * (1 - Math.exp(-le / mean)));
      histograms.push(`${config.histogram}_bucket{${labels},le="${le}"} ${below[j]} ${t}`);
    });
    histograms.push(`${config.histogram}_bucket{${labels},le="+Inf"} ${count} ${t}`);
    histograms.push(`${config.histogram}_count{${labels}} ${count} ${t}`);
    histograms.push(`${config.histogram}_sum{${labels}} ${sum.toFixed(3)} ${t}`);
    gauges.push(`${config.gauge}{${labels}} ${Math.round(requests * (incident ? 20 : 0.5))} ${t}`);
  }
}

const sortBySeries = (lines: string[]) =>
  lines
    .map((line, order) => ({ line, order, series: line.slice(0, line.lastIndexOf('} ') + 1) }))
    .sort((a, b) => (a.series === b.series ? a.order - b.order : a.series < b.series ? -1 : 1))
    .map(({ line }) => line);

const output = [
  `# TYPE ${config.counter} counter`,
  ...sortBySeries(counters),
  `# TYPE ${config.histogram} histogram`,
  ...sortBySeries(histograms),
  `# TYPE ${config.gauge} gauge`,
  ...sortBySeries(gauges),
  '# EOF',
];
console.log(output.join('\n'));
