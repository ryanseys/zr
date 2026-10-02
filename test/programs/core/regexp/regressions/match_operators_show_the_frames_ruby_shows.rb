# `=~` runs with no frame, as ruby's opt_regexpmatch2 instruction does,
# while match, match? and === keep their own; each sets the caller's $~.
s = "\xff".force_encoding("UTF-8")
[-> { /c/ =~ s }, -> { s =~ /c/ }, -> { /c/.match(s) }, -> { /c/ === s }, -> { /c/.match?(s) },
 -> { s.match(/c/) }, -> { re = /c/; re =~ s }, -> { case s; when /c/ then 1; end }].each do |l|
  l.call
rescue ArgumentError => e
  p e.backtrace_locations.map(&:label)
end

def show(m) = p(m && m[0])
p(/b/ =~ "abc"); show $~
p("abc" =~ /c/); show $~
p(/z/ === "abc"); show $~
p(/a/ === "abc"); show $~
p(/x/ =~ "abc"); show $~
