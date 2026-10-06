# STDOUT/STDERR (constants) .puts/.print with a COMPOUND-expression argument --
# format/sprintf/Array#join, array literals, a block call. Each argument is
# fully evaluated before the write.

STDOUT.puts(format("x=%d", 5))
STDOUT.puts(sprintf("y=%d", 7))
STDOUT.puts([1, 2, 3].join(","))
STDOUT.print(format("p=%d", 9))
STDOUT.print("\n")
STDOUT.puts format("noparen=%d", 11)   # no parens -- same lowering
STDOUT.puts([10, 20].map { |x| x * 2 }.join("-"))

# Simpler argument forms must also work.
m = format("bound=%d", 42)
STDOUT.puts(m)                          # bind to a local first
STDOUT.puts("a".upcase)                 # inline call that is NOT a compound expr
STDOUT.puts("z=%d" % 3)                 # `%` instead of format(...)

# puts adds a newline after EACH argument, and does NOT double a newline when
# the argument already ends in one.
STDOUT.puts("a", "b", "c")              # a\nb\nc\n
STDOUT.puts("already\n")                # already\n (no extra blank line)
STDOUT.puts(format("m=%d", 1), format("n=%d", 2))
STDOUT.puts                             # a single blank line
STDOUT.puts("abc"[10])                  # nil (out-of-range index) -> blank line
STDOUT.print                            # print with no args -> nothing (no empty ({}) )
STDOUT.puts("dprint-guard")

# STDERR goes to stderr (asserted against the .err.expected sidecar).
STDERR.puts(format("err=%d", 5))
STDERR.print(sprintf("errp=%d\n", 6))
STDERR.puts("e1", "e2")                 # e1\ne2\n
STDERR.puts("edone\n")                  # edone\n (no double newline)
