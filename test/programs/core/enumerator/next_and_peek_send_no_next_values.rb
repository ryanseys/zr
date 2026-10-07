# next and peek take their values as CRuby's C does: no frame of
# next_values shows under them, and a redefined next_values does not
# change them.

en = [1, 2].each
en.next
en.next
begin
  en.next
rescue StopIteration => s
  p s.backtrace
  p s.cause&.backtrace
end
begin
  en.next
rescue StopIteration => s
  p s.backtrace
  p s.cause&.backtrace
end
def m = [].each.next
begin
  m
rescue StopIteration => s
  p s.backtrace
end
e2 = [1, [2, 3], []].each
p e2.peek, e2.next, e2.peek_values, e2.next_values, e2.peek, e2.next
pv = [[4, 5]].each
a = pv.peek
a << 6
p pv.peek, pv.next_values
fr = [1].each.freeze
begin
  fr.next
rescue => err
  p err.class
end
class Enumerator
  def next_values = [:redefined]
end
p [7].each.next
