# Every built-in CLASS is subclassable (`zr_abi::NOT_PAYLOAD_ROOTS` is a
# denylist of the shapes that are not payload wrappers, not an allowlist
# of the ones that are). What is left is the two superclasses RUBY
# refuses, and zr compiles each into ruby's own raise rather than a
# compile error naming zr.

begin
  class WantsModule < Comparable
  end
rescue TypeError => e
  puts "module: #{e.message}"
end
begin
  class WantsClass < Class
  end
rescue TypeError => e
  puts "class: #{e.message}"
end
