# CRuby writes some core methods in Ruby, and a :line TracePoint sees
# each line that their bodies run. zr fires those lines when the build
# can know them: when every line before the last makes no call and has
# no branch (GC.start, then, a call of times without a block). A body
# that loops, branches or calls before its last line (times with a
# block, tap, first with a count) fires no :line in zr.
def internal_lines
  lines = []
  TracePoint.new(:line) do |tp|
    lines << "#{tp.path}:#{tp.lineno} #{tp.method_id}" if tp.path.start_with?("<internal:")
  end.enable { yield }
  lines
end

p internal_lines { 2.times { } }
p internal_lines { 1.tap { } }
p internal_lines { [1, 2].first(1) }
p internal_lines { loop { break } }
