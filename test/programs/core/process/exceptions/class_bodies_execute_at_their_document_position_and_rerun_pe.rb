# Real Ruby runs a class/module body WHERE IT APPEARS, interleaved
# with surrounding top-level code, re-executing each reopen's body at
# its own site; a rescued raise inside a module body shows the
# `<module:M>` frame and `<main>` at the `module` keyword's line.

puts "top1"
class Foo
  puts "body1"
end
puts "top2"
class Foo
  puts "body2"
end
class Outer
  puts "outer start"
  class Inner
    puts "inner body"
  end
  puts "outer end"
end
module M
  begin
    raise "inmod"
  rescue => e
    puts "rescued: #{e.backtrace[0]}"
    puts "from: #{e.backtrace[1]}"
  end
end
puts "top3"
