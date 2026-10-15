# readpartial, read_nonblock and sysread convert the length as a long
# first (a Float truncates, to_int is called), then the buffer, which
# must be a modifiable String; read_nonblock checks `exception:` after
# both. sysread makes no buffer of a negative size, and read(2) refuses
# one for a buffer it was given.
class Two
  def to_int = 2
  def inspect = "Two"
end

def stream
  r, w = IO.pipe
  w.write("hello world")
  w.close
  r
end

cases = [
  [nil], [nil, 3], [1, 3], [1, :s], [-1], [-1, 3], [-1, +""], [Two.new], ["2"], [2.9], [0.5], [2.5, +"buf"],
  [2, "frozen".freeze], [0, "frozen".freeze], [0, 3], [2**64], [Float::NAN],
]
%i[readpartial read_nonblock sysread].each do |name|
  cases.each do |args|
    r = stream
    result = r.public_send(name, *args)
    puts "#{name}#{args.inspect}: #{result.inspect}"
  rescue => e
    puts "#{name}#{args.inspect}: #{e.class}: #{e.message}"
  ensure
    r&.close
  end
end

def try(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("bad exception: with a bad length") { stream.read_nonblock(nil, exception: 1) }
try("bad exception: with a bad buffer") { stream.read_nonblock(1, 3, exception: 1) }
try("bad exception:") { stream.read_nonblock(1, exception: 1) }
try("no exception at the end") do
  r, w = IO.pipe
  w.close
  buffer = +"old"
  [r.read_nonblock(4, buffer, exception: false), buffer]
end
try("sysread of a file") { File.open(__FILE__) { |f| f.sysread(-1, +"") } rescue $!.class }

# pread reads its length as a size_t, which wraps to a negative long from
# 2**63 up; a negative one makes no new buffer, and pread(2) refuses it
# for a buffer that was given.
File.open(__FILE__) do |f|
  [[-1, 0], [-1, 0, +""], [-1, 0, 3], [-1, nil], [2**64, 0], [2**64 - 1, 0, 3], [2**63, 0], [2**63, 0, +""],
   [1, -1], [1, 0, "f".freeze], [0, 0, "f".freeze], [nil, 0], [2.5, 0], [2, 0, +"zz"]].each do |args|
    puts "pread#{args.inspect}: #{f.pread(*args).inspect}"
  rescue => e
    puts "pread#{args.inspect}: #{e.class}"
  end
end
