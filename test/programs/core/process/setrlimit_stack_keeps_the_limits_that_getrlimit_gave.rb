# Process.setrlimit(:STACK) changes the limit of the process's stack, as
# for any other resource: the program runs on a stack of its own, so the
# system lets it.
cur, max = Process.getrlimit(:STACK)
p Process.setrlimit(:STACK, cur, max)
p Process.getrlimit(:STACK) == [cur, max]
p Process.setrlimit("STACK", cur, max)
p Process.setrlimit(Process::RLIMIT_STACK, cur, max)
p Process.getrlimit(:STACK) == [cur, max]

# The program's own stack keeps its depth after the change.
def count(n)
  $depth = n
  count(n + 1)
end
begin
  count(0)
rescue SystemStackError => e
  p e.message, $depth > 9_000
end
