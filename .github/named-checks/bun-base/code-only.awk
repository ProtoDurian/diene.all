# Prints a shell line with quoted text removed; $(...) and backticks, even inside "...", stay code.
{
  n = split($0, ch, ""); out = ""; top = 1; st[1] = "c"; dp[1] = 0
  for (i = 1; i <= n; i++) {
    c = ch[i]; s = st[top]
    if (s == "q") { if (c == "'") top--; continue }
    if (c == "\\") { i++; continue }
    if (s == "d") {
      if (c == "\"") top--
      else if (c == "$" && ch[i + 1] == "(") { out = out "$("; i++; st[++top] = "c"; dp[top] = 0 }
      else if (c == "`") { out = out "("; st[++top] = "b" }
      continue
    }
    if (c == "'") { st[++top] = "q"; continue }
    if (c == "\"") { st[++top] = "d"; continue }
    if (c == "`") { out = out (s == "b" ? ")" : "("); if (s == "b") top--; else st[++top] = "b"; continue }
    if (c == "(") dp[top]++
    if (c == ")") { if (top > 1 && s == "c" && dp[top] == 0) top--; else dp[top]-- }
    out = out c
  }
  print out
}
