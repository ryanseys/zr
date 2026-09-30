# Recursion: each invocation owns its own proc-return frame, so the return
# targets the correct method instance.
def countdown(n, acc)
  proc { return acc if n == 0 }.call
  countdown(n - 1, acc + n)
end
p countdown(5, 0)

