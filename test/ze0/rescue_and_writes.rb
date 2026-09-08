# frozen_string_literal: true

# `retry` runs the whole `begin` again, leaving the clause it is written
# in -- and the `$!` that clause holds -- behind.

tries = 0
begin
  tries += 1
  raise "boom" if tries < 3
  p [:ok, tries]
rescue
  retry
end

def flaky
  n = 0
  begin
    n += 1
    raise ArgumentError if n < 2
    n
  rescue ArgumentError
    retry
  end
end
p flaky

# A `*errs` spreads its elements in, so how many classes a clause names
# is a run-time fact.
errs = [TypeError, ArgumentError]
begin
  raise ArgumentError, "bad"
rescue *errs => e
  p [:caught, e.class, e.message]
end

begin
  raise "plain"
rescue *errs
  p :never
rescue => e
  p [:standard, e.message]
end

# The binding is an ordinary write target, so an ivar or a global takes
# a reference of its own.
class Holder
  attr_reader :e

  def run
    raise "held"
  rescue => @e
    @e.message
  end
end
h = Holder.new
p h.run
p h.e.message

begin
  raise "global"
rescue => $caught
end
p $caught.message

# A write answers the value ASSIGNED, whatever the setter returns.
class Box
  attr_accessor :v

  def w=(x)
    @v = x
    :ignored
  end

  def []=(_k, x)
    @v = x
    :ignored
  end
end
b = Box.new
p(b.w = 3)
p(b[1] = 4)
p(b.v ||= 9)
p(b.v += 1)

# Safe navigation: a nil receiver answers nil and runs nothing.
o = nil
p(o&.v = 3)
p(b&.v = 11)
p(b&.v ||= 12)
p(b&.v += 1)
p b.v
__END__
[:ok, 3]
2
[:caught, ArgumentError, "bad"]
[:standard, "plain"]
"held"
"held"
"global"
3
4
4
5
nil
11
11
12
12
