# IO: a write after a buffered read goes where the reader is, a read
# after a buffered write sees it, read(n) does not read ahead, seek
# takes CRuby's whence names, and offsets and limits are C integers.
require "tmpdir"

def show
  p yield
rescue => e
  p e.class, e.message
end

Dir.mktmpdir do |dir|
  path = File.join(dir, "digits.txt")
  File.write(path, "0123456789" * 3)

  File.open(path, "r+") do |f|
    f.read(5)
    f.write("abcd")
    f.rewind
    p f.read
  end

  File.write(path, "0123456789" * 3)
  File.open(path, "r+") do |f|
    f.write("abcde")
    p f.read(10)
  end

  File.open(path) do |f|
    f.read(15)
    p f.sysread(5)
    p f.sysseek(-5, IO::SEEK_CUR)
  end

  File.open(path) do |f|
    buffer = +"existing"
    p f.sysread(0, buffer)
    f.seek(0, :END)
    show { f.sysread(1, buffer) }
    p buffer
    show { f.seek(0, :end) }
    show { f.seek(2**64) }
    show { f.gets(2**64) }
    show { f.advise("normal") }
    show { f.advise(:normal, 2**64) }
    holder = Object.new
    def holder.to_str = +"text"
    show { f.read(2, holder) }
  end

  File.open(path, "w+") do |f|
    f.pwrite("bar", 3)
    f.write("foo")
    p f.pread(6, 0)
    show { f.close_write }
  end

  File.open(path) do |f|
    p f.write("")
    p f.dup.close_on_exec?
    p f.dup.autoclose?
    p f.readlines(chomp: true, foo: :bar).size
  end

  $_ = "before"
  IO.foreach(path) { |line| p $_.equal?(line) }
  p $_

  p IO.write(path, "hi", open_args: ["w", nil, { encoding: Encoding::UTF_32LE }])
  p IO.read(path, open_args: [{ encoding: Encoding::US_ASCII }]).encoding
  show { IO.read(path, 0, -1) }
  p IO.sysopen(path, nil, nil).positive?
end

show { IO.try_convert(BasicObject.new) }
bad = Object.new
def bad.to_io = "text"
show { IO.try_convert(bad) }

line = Object.new
def line.to_ary = ["from to_ary"]
$stdout.puts(line)
IO.popen(["sh", "-c", "echo out; echo err >&2", { err: [:child, :out] }], "r") { |io| p io.read }
