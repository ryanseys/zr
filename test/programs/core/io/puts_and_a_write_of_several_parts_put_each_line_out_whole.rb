# rb_io_writev writes the parts of one `write`, and a line with the newline
# that `puts` adds, at once: no other thread and no finalizer writes
# between them, whether the stream is buffered or each write goes out.
r, w = IO.pipe
writers = 4.times.map do |t|
  Thread.new do
    300.times do |i|
      w.puts "thread #{t} line #{i} #{'x' * 40}"
      w.write("part one of #{t}/#{i} ", "part two of #{t}/#{i}\n")
      Thread.pass if (i % 7).zero?
    end
  end
end
reader = Thread.new { r.read }
writers.each(&:join)
w.close
lines = reader.value.lines
p lines.size
p lines.count { _1.match?(/\Athread \d line \d+ x{40}\n\z/) }
p lines.count { _1.match?(%r{\Apart one of (\d/\d+) part two of \1\n\z}) }

w = IO.new(IO.sysopen(IO::NULL, "w"))
w.sync = true
p w.write("a", "b", 3, :c)
p w.write
w.close

# A part that is not a String: a buffered stream converts and writes one
# part at a time, so what its to_s writes goes before it. A sync stream
# converts every part first, then writes them all.
class Noisy
  def initialize(io, n) = (@io, @n = io, n)

  def to_s
    @io.print("[c#{@n}]")
    "<#{@n}>"
  end
end

[false, true].each do |sync|
  r, w = IO.pipe
  w.sync = sync
  p w.write(Noisy.new(w, 1), "s", Noisy.new(w, 2))
  w.close
  p [sync, r.read]
end
