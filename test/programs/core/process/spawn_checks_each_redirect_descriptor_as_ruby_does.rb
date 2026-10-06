# Each descriptor that a spawn's redirect names is a Fixnum that fits an
# int and is not negative, :in, :out or :err, or an IO (or what converts
# to one); a key that is none of these is a wrong option.
class Stream
  def to_io = STDOUT
end

[{ 1 => Process }, { [Process] => 1 }, { [1, STDOUT] => 2 }, { -1 => 2 }, { [-1] => 2 },
 { 3 => [:child, -1] }, { 3 => [:child, :nope] }, { 3 => [:child, Process] }, { -1 => :close },
 { 2**40 => 1 }, { 2**70 => 1 }, { [2**70] => 1 }, { 1.5 => 1 }, { [:out] => File::NULL },
 { [:nope] => 1 }, { [Stream.new] => File::NULL }, { Stream.new => File::NULL }, { "1" => 1 }].each do |opt|
  pid = Process.spawn("true", opt)
  Process.wait(pid)
  p [opt.keys.first.class, :ok]
rescue ArgumentError, TypeError, RangeError => e
  p [opt.keys.first.class, e.class, e.message]
end
