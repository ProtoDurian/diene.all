# Synthetic pino-style log lines as VictoriaLogs JSON lines. Run: awk [-v identity=…] -f generate-logs.awk > logs.json
BEGIN {
  # Your service and module as your log queries select them (or pass -v identity=…).
  if (identity == "") identity = "service=sample,module=api"
  landscapes = "pichu=1 raichu=0.25"
  hours = 6; step = 60; incident_from = 2.5; incident_to = 3.5
  # The newest line of the first landscape is an error with this trace id, stamped now; trace.json is that trace.
  known_trace = "4bf92f3577b34da6a3ce929d0e0e4736"

  # One line per kind of log line: pino level (30 info, 40 warn, 50 error), lines per minute normally, during the incident, msg.
  kinds = \
    "30  2    1.5  request completed\n" \
    "40  0.1  1    slow upstream\n" \
    "50  0.05 3    request failed"

  "date +%s" | getline now
  end = int(now / step) * step
  start = end - hours * 3600
  nl = split(landscapes, ls, " ")
  nk = split(kinds, kind, "\n")
  for (j = 1; j <= nl; j++) stream(ls[j], j)
}

function stream(landscape, j,    scale, labels, p, kv, pair, svc, i, t, h, k, f, rate, due, n, c, msg) {
  split(landscape, scale, "=")
  labels = "\"durian.cloud.landscape\":\"" scale[1] "\""
  p = split(identity, kv, ",")
  for (i = 1; i <= p; i++) { split(kv[i], pair, "="); if (pair[1] == "service") svc = pair[2]; sub(/=/, "\":\"", kv[i]); labels = labels ",\"durian.cloud." kv[i] "\"" }
  labels = labels ",\"durian.cloud.platform\":\"sample\",\"service.name\":\"" svc "\",\"service.namespace\":\"sample\",\"deployment.environment.name\":\"" scale[1] "\",\"k8s.namespace.name\":\"sample\""
  sid = labels
  for (t = start; t <= end; t += step) {
    h = (t - start) / 3600; c = 0
    for (k = 1; k <= nk; k++) {
      split(kind[k], f, " +")
      rate = (h > incident_from && h < incident_to ? f[3] : f[2]) * scale[2]
      due[k] += rate
      while (due[k] >= 1) {
        due[k]--; n++; c++
        msg = kind[k]; sub(/^[0-9]+ +[0-9.]+ +[0-9.]+ +/, "", msg)
        entry(f[1], t, c, scale[1] "-" j, msg, sprintf("%08x%08x%08x%08x", t, j, k, n))
      }
    }
  }
  if (j == 1) entry(50, now, 999, scale[1] "-" j, "request failed", known_trace)
}

# One line: the stream fields, severity, trace context and the stored message; error lines add the error message.
function entry(level, t, ms, host, msg, id,    line) {
  line = sprintf("{%s,\"_time\":\"%d%03d000000\",\"_msg\":\"%s\",\"severity_number\":%d,\"severity_text\":\"%s\",\"k8s.pod.name\":\"%s\",\"trace_id\":\"%s\",\"span_id\":\"%s\"", \
    sid, t, ms, msg, level, (level == 50 ? "error" : (level == 40 ? "warn" : "info")), host, id, substr(id, 17))
  if (level == 50) line = line ",\"err.message\":\"upstream timeout after 2000 ms\""
  print line ",\"status\":" (level == 50 ? 503 : 200) "}"
}
