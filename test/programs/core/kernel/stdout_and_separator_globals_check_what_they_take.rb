# $stdout, $>, $stderr and the separators check what a program assigns:
# an output must have a write method, a separator must be a String.
$VERBOSE = nil
def t(label)
  yield
  STDOUT.puts "#{label}: took it"
rescue TypeError => e
  STDOUT.puts "#{label}: #{e.class}: #{e.message}"
end

t(:stdout) { $stdout = 1 }
t(:gt) { $> = Object.new }
t(:stderr) { $stderr = nil }
alias $out $stdout
t(:alias) { $out = 2 }
STDOUT.puts $stdout.equal?(STDOUT), $stderr.equal?(STDERR)

writer = Object.new
def writer.write(*parts) = STDOUT.write("[", *parts, "]")
$> = writer
puts "through writer"
$stdout = STDOUT
STDOUT.puts $stdout.equal?(STDOUT)

t(:ors) { $\ = 1 }
t(:ofs) { $, = :sym }
t(:rs) { $/ = 5 }
$\ = "!\n"
print "with ors"
$\ = nil
STDOUT.puts [$\, $,].inspect
