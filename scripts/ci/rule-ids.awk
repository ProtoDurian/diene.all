{
  n = split($0, tokens, /[^A-Za-z0-9_!-]+/)
  for (i = 1; i <= n; i++) {
    t = tokens[i]
    if (t ~ /^(R[0-9]+|S[0-9]+|OD-[0-9]+|RB-[0-9]+|GAP-[0-9]+|!A[0-9]+)$/ && t !~ /^(S3|R2)$/) {
      printf "%s:%d: corpus rule ID %s\n", FILENAME, FNR, t
      found = 1
    }
  }
}

END { exit found }
