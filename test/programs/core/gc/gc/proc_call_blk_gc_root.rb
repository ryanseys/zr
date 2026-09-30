# A method with a real &blk param (no yield; a Thread.new branch that never
# runs also captures blk) calls blk many times. A GC inside the block body
# must keep the proc alive for the next blk.call. Both call shapes are
# covered: a toplevel def and a module class method.

def each_i(n, &blk)
  Thread.new { blk.call(0) }.join if n < 0
  i = 0
  while i < n
    blk.call(i)
    i += 1
  end
end

module Parallel
  def self.each_index(n, &blk)
    Thread.new { blk.call(0) }.join if n < 0
    i = 0
    while i < n
      blk.call(i)
      i += 1
    end
  end
end

acc = Array.new(5, 0.0)
each_i(5) do |i|
  GC.start
  acc[i] += 1.5 * i
end
Parallel.each_index(5) do |i|
  GC.start
  acc[i] += 2.5 * i
end
tot = 0.0
i = 0
while i < 5; tot += acc[i]; i += 1; end
puts "tot=#{tot}"
