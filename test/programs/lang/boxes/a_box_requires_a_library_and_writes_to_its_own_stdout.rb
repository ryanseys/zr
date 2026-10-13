# A box that requires a library sees its constants, and Kernel's puts and
# warn in the box write to the box's own $stdout and $stderr, while main's
# stay as they were.
b = Ruby::Box.new
p b.eval('require "stringio"'), b.eval("defined?(StringIO)")
p b.eval(<<~'CODE')
  o, e = $stdout, $stderr
  $stdout, $stderr = StringIO.new, StringIO.new
  puts "standard out"
  print "printed", "\n"
  warn "standard err"
  $stdout.write("w")
  r = [$stdout.string, $stderr.string]
  $stdout, $stderr = o, e
  r
CODE
p $stdout.equal?(STDOUT), $stderr.equal?(STDERR)
puts "main out"
p b.eval('require "stringio"')
