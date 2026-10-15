# A range literal whose ends do not compare raises ArgumentError at the
# literal's line, and an end's `<=>` sees that line as its caller.
class Ends
  def <=>(other)
    p [:cmp, caller_locations(1, 1).first.lineno]
    nil
  end
end

def line_of
  yield
rescue ArgumentError => e
  p [e.message, e.backtrace_locations.first.lineno]
end

to = Object
a = []
line_of do
  a..to
end
line_of { Ends.new..Ends.new }
line_of do
  x = Ends.new

  x...x
end
p (1..2), ("a"..), (..3)
