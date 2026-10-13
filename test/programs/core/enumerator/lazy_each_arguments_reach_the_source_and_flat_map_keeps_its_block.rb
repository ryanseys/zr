# The arguments that Lazy#each gets go to the source's each, also when
# a later stage reads that lazy (io.lazy.each("").map reads paragraphs,
# one gets each). Lazy#flat_map gives an object that has force and each a
# block that still works after the walk ends; it returns what it got,
# packed (ruby #22388).
require "tmpdir"

Dir.mktmpdir do |dir|
  path = File.join(dir, "text.txt")
  File.write(path, "\n\n# a\n# b\n\nclass Foo\n  x\nend\n\nmore\n\nand more\n")
  File.open(path) do |f|
    found = f.lazy.each("").map { |pa| pa[/\A\s*(.*)/, 1] }.find { |l| l.start_with?("class") }
    p [found, f.lineno]
  end
  File.open(path) do |f|
    p f.lazy.each("").select { |pa| pa.include?("more") }.map(&:chomp).first(2), f.lineno
  end
  File.open(path) do |f|
    p f.lazy.each("").with_index.map { |pa, i| [i, pa.lines.size] }.to_a
  end
  File.open(path) do |f|
    lz = f.lazy.each("\n", 3)
    p lz.map(&:size).first(4)
  end
  p (1..3).lazy.each.map { _1 * 2 }.to_a
end

enum = Object.new
class << enum
  include Enumerable
  attr_reader :block
  def force = true
  def each(&block) = @block = block
end
yielded = []
got = []
[enum].lazy.flat_map { |x| yielded << x; x }.each { |*x| got << x }
GC.start
p enum.block.call(42), enum.block.call(1, 2), enum.block.call, got, yielded.size

# An object with force and each gives its values one at a time.
inner = Object.new
def inner.force = true
def inner.each
  yield 1
  yield 2, 3
  yield
end
p [inner].lazy.flat_map { _1 }.map { |*a| a }.to_a
p [inner].lazy.flat_map { _1 }.to_a, [[1, [2]], 3].lazy.flat_map { _1 }.to_a
