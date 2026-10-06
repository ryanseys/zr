# `:rescue` fires where the exception is caught, not where it was raised:
# in the frame that holds the matching clause, at that clause's line, with
# the exception still in `raised_exception`. A clause that does not match
# fires nothing, so the line names the one that did.
#
# `TracePoint.new` with no events asks for all of them, which is the form
# anyone writes first.
seen = []
tp = TracePoint.new(:raise, :rescue) { |t| seen << [t.event, t.raised_exception.class.to_s, t.lineno] }

def inner = raise(ArgumentError, "x")

def outer
  inner
rescue ArgumentError
  :caught
end

tp.enable do
  outer
  begin
    [1].each { raise TypeError }
  rescue TypeError
    nil
  end
  begin
    raise KeyError
  rescue ArgumentError
    nil
  rescue KeyError
    nil
  end
end

seen.each { |row| p row }
p TracePoint.new { |t| }.class
