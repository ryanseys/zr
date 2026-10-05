# An error raised inside an external enumeration (Enumerator#next) shows
# Enumerator#each under the method, with the method's file and no line,
# as CRuby's cfunc frame at the bottom of the fiber does. zr's backtrace
# leaves that frame out: its fiber's helper calls each on its own receiver.
def gen
  return to_enum(__method__) unless block_given?
  raise "in gen"
  yield 1
end
begin
  gen.next
rescue => e
  p e.backtrace.map { |l| l.sub(/\A.*?:(\d+:)?in /) { "#{$1 ? "LINE:" : ""}in " } }
end
