# Synthetic OpenMetrics for promtool backfill. Run: awk -f generate-metrics.awk > metrics.om
BEGIN {
  # Your dashboard's platform, service and module, as its queries select them.
  identity = "platform=sandbox,service=sample,module=api"
  landscapes = "pichu=1 raichu=0.25"
  hours = 6; step = 30; incident_from = 2.5; incident_to = 3.5
  buckets = "0.01 0.025 0.05 0.1 0.25 0.5 1 2.5"

  # One line per metric and label set: type, name, labels (or -), normal value, incident value.
  # counter: per second (name ends in _total); gauge: the value; histogram: mean seconds, 10 per second.
  metrics = \
    "counter   sample_requests_total            outcome=success  300   270\n" \
    "counter   sample_requests_total            outcome=error    1.2   30\n" \
    "histogram sample_request_duration_seconds  -                0.07  0.35\n" \
    "gauge     sample_queue_depth               -                20    400"

  "date +%s" | getline now
  end = int(now / step) * step
  start = end - hours * 3600
  nb = split(buckets, le, " ")
  nl = split(landscapes, ls, " ")
  n = split(metrics, rows, "\n")
  for (r = 1; r <= n; r++) {
    split(rows[r], f, " +")
    family = f[1] == "counter" ? substr(f[2], 1, length(f[2]) - 6) : f[2]
    if (!(family in typed)) { typed[family] = f[1]; order[++families] = family }
    members[family] = members[family] " " r
  }
  for (k = 1; k <= families; k++) {
    family = order[k]
    print "# TYPE " family " " typed[family]
    nr = split(substr(members[family], 2), rs, " ")
    for (m = 1; m <= nr; m++) for (j = 1; j <= nl; j++) series(rows[rs[m]], ls[j])
  }
  print "# EOF"
}

function quote(set,    out, i, p, kv) {
  if (set == "-") return ""
  p = split(set, kv, ",")
  for (i = 1; i <= p; i++) { sub(/=/, "=\"", kv[i]); out = out "," kv[i] "\"" }
  return out
}

function series(row, landscape,    f, scale, labels, t, i, wave, value, total, count, sum, below, b, obs) {
  split(row, f, " +")
  split(landscape, scale, "=")
  labels = "landscape=\"" scale[1] "\"" quote(identity) quote(f[3])
  for (b = 1; b <= nb; b++) below[b] = 0
  for (t = start; t <= end; t += step) {
    i = (t - start) / 3600
    wave = 1 + 0.2 * sin(i * 3)
    value = (i > incident_from && i < incident_to ? f[5] : f[4]) * wave
    if (f[1] == "gauge") {
      out[t] = sprintf("%s{%s} %.0f %d", f[2], labels, value * scale[2], t)
    } else if (f[1] == "counter") {
      total += value * scale[2] * step
      out[t] = sprintf("%s{%s} %.0f %d", f[2], labels, total, t)
    } else {
      obs = int(10 * scale[2] * step * wave + 0.5)
      count += obs; sum += obs * value
      for (b = 1; b <= nb; b++) { below[b] += int(obs * (1 - exp(-le[b] / value)) + 0.5); hist[b, t] = below[b] }
      hist["+Inf", t] = count; hist["count", t] = count; hist["sum", t] = sum
    }
  }
  if (f[1] != "histogram") { for (t = start; t <= end; t += step) print out[t]; return }
  for (b = 1; b <= nb; b++) for (t = start; t <= end; t += step) printf "%s_bucket{%s,le=\"%s\"} %d %d\n", f[2], labels, le[b], hist[b, t], t
  for (t = start; t <= end; t += step) printf "%s_bucket{%s,le=\"+Inf\"} %d %d\n", f[2], labels, hist["+Inf", t], t
  for (t = start; t <= end; t += step) printf "%s_count{%s} %d %d\n", f[2], labels, hist["count", t], t
  for (t = start; t <= end; t += step) printf "%s_sum{%s} %.3f %d\n", f[2], labels, hist["sum", t], t
}
