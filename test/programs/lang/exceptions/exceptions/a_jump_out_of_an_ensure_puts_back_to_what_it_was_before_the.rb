# An ensure that ends in a jump drops the exception it ran for, and $!
# goes back to what it held before the begin, as it does when the
# ensure falls through. The dropped exception is then no later
# raise's cause.
[1].each { begin; raise "by break"; ensure; break; end }
p $!
[1].each { begin; raise "by next"; ensure; next; end }
p $!
def by_return
  begin; raise "by return"; ensure; return :back; end
end
p [by_return, $!]
l = -> { begin; raise "by lambda"; ensure; return :l; end }
p [l.call, $!]
p catch(:t) { begin; raise "by throw"; ensure; throw :t, :thrown; end }
p $!
begin
  raise "outer"
rescue
  [1].each { begin; raise "inner"; ensure; break; end }
  p $!.message
end
begin
  raise "final"
rescue => e
  p e.cause
end
