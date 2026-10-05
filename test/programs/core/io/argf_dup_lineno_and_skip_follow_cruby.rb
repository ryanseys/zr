# ARGF over three files: a dup reads on its own, rewind and lineno set $.
# as CRuby does, and skip inside each_line, each_byte, each_char and
# each_codepoint goes on with the next file.
require "tmpdir"

dir = Dir.mktmpdir
paths = [%w[1 2], %w[3 4], %w[5 6]].each_with_index.map do |lines, i|
  path = File.join(dir, "f#{i}")
  File.write(path, lines.map { |l| "#{l}\n" }.join)
  path
end
wide = %W[あ い う].each_with_index.map do |s, i|
  path = File.join(dir, "w#{i}")
  File.write(path, s, mode: "w:utf-8")
  path
end

# Each script runs in a child, so ARGF and $. start fresh.
def script(name, argv)
  $stdout.flush
  pid = fork do
    ARGV.replace(argv)
    puts "== #{name}"
    yield
    $stdout.flush
    exit!(0)
  end
  Process.wait(pid)
end

script("dup", paths) do
  a = ARGF
  b = a.dup
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  a.rewind
  b.rewind
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  a.rewind
  b.rewind
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
  p [a.gets.chomp, a.lineno, b.gets.chomp, b.lineno]
end

script("lineno", paths) do
  a = ARGF
  a.gets; p($.)
  a.gets; p($.)
  a.gets; p($.)
  a.rewind; p($.)
  a.gets; p($.)
  a.gets; p($.)
  a.rewind; p($.)
  a.gets; p($.)
  a.lineno = 1000; p($.)
  a.gets; p($.)
  a.gets; p($.)
  $. = 2000
  a.gets; p($.)
  a.gets; p($.)
end

script("lineno of a dup", paths) do
  a = ARGF.dup
  a.gets; p($.)
  a.gets; p($.)
  a.gets; p($.)
  a.rewind; p($.)
  a.gets; p($.)
  a.gets; p($.)
  a.gets; p($.)
  a.lineno = 1000; p($.)
  a.gets; p($.)
  a.gets; p($.)
  $. = 2000
  a.gets; p($.)
  a.gets; p($.)
end

script("skip in each_line", paths) { ARGF.each_line { |l| print l; ARGF.skip } }
script("skip and gets in each_line", paths) do
  ARGF.each_line { |l| ARGF.skip; puts [l, ARGF.gets].map { |s| s ? s.chomp : s.inspect }.join("+") }
end
script("skip in each_byte", paths) { ARGF.each_byte { |b| print b; ARGF.skip } }
puts
script("skip in each_char", wide) { ARGF.each_char { |c| print c; ARGF.skip } }
puts
script("skip in each_codepoint", wide) { ARGF.each_codepoint { |c| printf "%x:", c; ARGF.skip } }
puts

# $-i turns the edit in place on and off between files.
edit = [%w[1 2], %w[3 4], %w[5 6]].each_with_index.map do |lines, i|
  path = File.join(dir, "e#{i}")
  File.write(path, lines.map { |l| "#{l}\n" }.join)
  path
end
script("edit in place", edit) do
  $-i = ".bak"
  puts ARGF.gets.chomp + ".new"
  puts ARGF.gets.chomp + ".new"
  p $-i
  $-i = nil
  puts ARGF.gets.chomp + ".new"
  puts ARGF.gets.chomp + ".new"
  p $-i
  $-i = ".bak"
  puts ARGF.gets.chomp + ".new"
  p $-i
  $-i = nil
  puts ARGF.gets.chomp + ".new"
end
$stdout.flush
edit.each { |path| p [File.basename(path), File.read(path), File.exist?("#{path}.bak") && File.read("#{path}.bak")] }

def show
  p yield
rescue ArgumentError => e
  p [e.class, e.message]
end
show { ARGF.class.new.inplace_mode = "a\0" }
show { ARGF.class.new.inplace_mode = "-bak".encode("UTF-16LE") }

wide_name = File.join(dir, "argf-テスト")
File.write(wide_name, "foo")
script("suffix in UTF-16", []) do
  argf = ARGF.class.new(wide_name)
  argf.inplace_mode = "-bak".encode(Encoding::UTF_16LE)
  begin
    argf.each { |s| puts "+" + s }
  ensure
    $stdout.close unless $stdout.equal?(STDOUT)
    $stdout = STDOUT
  end
end
p [File.read(wide_name), File.read("#{wide_name}-bak"), File.exist?("#{wide_name}-")]
