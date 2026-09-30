# The `io/console` rows are gated on the require, and touching an IO BEFORE
# that require must not close the gate for the rest of the program.
#
# Here `r.fileno` runs before the require. After the require, `echo?`,
# `raw` and `getch` must work, and `respond_to?` must agree with them.

r, w = IO.pipe
r.fileno # a call on the IO before the require

require "io/console"

p r.respond_to?(:echo?)
p r.respond_to?(:raw)
p IO.respond_to?(:console)

# A pipe is not a terminal, so the ANSWER is a syscall error -- which is the
# point: the row is reached at all.
begin
  r.echo?
rescue SystemCallError => e
  p e.class
end

begin
  r.raw { 1 }
rescue SystemCallError => e
  p e.class
end
