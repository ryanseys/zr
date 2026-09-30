# frozen_string_literal: true

# `ensure` runs its clause on the way out however the body leaves: a
# normal finish, a raise, or a jump the clause stands between.

log = []

def guard(log)
  log << :body
  :done
ensure
  log << :ensured
end

p guard(log), log

def raiser(log)
  log << :body
  raise ArgumentError, "boom"
ensure
  log << :ensured
end

begin
  raiser(log)
rescue ArgumentError => e
  p e.message
end
p log

# The clause runs after the `rescue` has already answered.
x = begin
  Integer("nope")
rescue ArgumentError
  :rescued
ensure
  log << :inner
end
p x, log

# `$!` names the exception being carried while the clause runs, and nil
# when nothing is being carried.
def carried
  raise "up"
ensure
  p $!.message
end

begin
  carried
rescue RuntimeError => e
  p e.message
end

def quiet
  :fine
ensure
  p $!
end
p quiet

# A raise from the clause itself wins over the one it was carrying.
def replaced
  raise ArgumentError, "first"
ensure
  raise TypeError, "second"
end

begin
  replaced
rescue TypeError => e
  p e.class, e.message
end

# A `next` written in a block inside the body lands in that block and
# never crosses the clause.
def counted(log)
  [1, 2, 3].map do |n|
    next 0 if n == 2

    n
  end
ensure
  log << :counted
end
p counted(log), log
# `value rescue fallback` is one bare clause over one expression, and a
# bare clause is `StandardError`: anything above it still leaves.
def boom = raise(ArgumentError, "no")
def fatal = raise(NotImplementedError, "up")

p((boom rescue :caught))
p(([1, 2].fetch(9) rescue :missing))
p(((1 + 1) rescue :never))

taken = boom rescue :assigned
p taken

@held = boom rescue :ivar
p @held

def returns_early
  return boom rescue :returned
end
p returns_early

begin
  p((fatal rescue :never))
rescue NotImplementedError => e
  p e.message
end

# The fallback is an ordinary expression, and it may raise in its turn.
begin
  p((boom rescue fatal))
rescue NotImplementedError => e
  p e.message
end

# `$!` is the exception for the fallback's whole run, and gone after.
p((boom rescue $!.message))
p $!

# One modifier inside another: the inner one catches first.
p((boom rescue (boom rescue :inner)))
# A jump the clause stands between travels as a signal, and the clause
# turns it back into the jump it was once it has run.
def crossed(log)
  out = []
  i = 0
  while i < 5
    i += 1
    begin
      next if i == 2
      break if i == 4

      out << i
    ensure
      log << [:crossed, i]
    end
  end
  out
end
p crossed(log), log

# Two clauses in a row: each runs, outermost last.
def twice
  seen = []
  [1, 2, 3].each do |n|
    begin
      begin
        break if n == 3
      ensure
        seen << [:inner, n]
      end
    ensure
      seen << [:outer, n]
    end
  end
  seen
end
p twice

# In a block the clause stands in front of the block's own boundary, so
# `next` still answers the block and `break` still leaves the send.
def in_a_block
  [1, 2, 3].map do |n|
    begin
      next :skipped if n == 2

      n
    ensure
      print "n#{n} "
    end
  end
end
p in_a_block

def broken
  [1, 2, 3].each do |n|
    begin
      break :stopped if n == 2
    ensure
      print "b#{n} "
    end
  end
end
p broken

# `break` supplies the loop's own value across the clause.
def valued
  i = 0
  while true
    i += 1
    begin
      break i * 10
    ensure
      print "v "
    end
  end
end
p valued

