# Ruby's C walks its own Arrays and Hashes directly, so a program's
# `each` runs only where ruby sends it by name.
$calls = 0
module CountEach
  def each(*, &) = ($calls += 1; super)
end
[Array, Hash, Range, Struct].each { |klass| klass.prepend(CountEach) }
Point = Struct.new(:x, :y)
sink = Object.new
def sink.write(*parts) = parts.sum(&:size)
checks = {
  "puts" => -> { $stdout = sink; puts [1, [2]], "a"; $stdout = STDOUT },
  "print" => -> { $stdout = sink; print "a", "b"; $stdout = STDOUT },
  "p" => -> { $stdout = sink; p 1, [2]; $stdout = STDOUT },
  "warn" => -> { $stderr = sink; warn "a", ["b"]; $stderr = STDERR },
  "pack" => -> { [1, 2].pack("CU") },
  "regexp" => -> { Regexp.new("[a-z]+\\d{2,}") },
  "join" => -> { File.join("a", ["b", "c"]) },
  "glob" => -> { Dir.glob([File.join(__dir__, "*"), __dir__]) { } },
  "sort_by!" => -> { [1].sort_by! { _1 } },
  "hash []" => -> { Hash[1, 2, 3, 4] },
  "values_at" => -> { [1, 2, 3].values_at(0, 1..2) },
  "union" => -> { [1].union([2], [3]); [1, 2].intersection([2], [2, 3]) },
  "literal min" => -> { x = 2; [x, 1, 3].min + [x, 1].max },
  "marshal" => -> { Marshal.load(Marshal.dump([Point.new(1, 2), 2**70])) },
  "match inspect" => -> { /(?<a>x)(y)?/.match("x").inspect },
  "proc inspect" => -> { proc { |a, b = 1, *c, d:, &e| }.inspect },
  "each_pair" => -> { Point.new(1, 2).each_pair { } },
  "eval" => -> { eval("[1, 2].map { |v| v + 1 }.sum") },
}
checks.each do |name, check|
  before = $calls
  check.call
  $stdout.write("#{name}: #{$calls - before}\n")
end
