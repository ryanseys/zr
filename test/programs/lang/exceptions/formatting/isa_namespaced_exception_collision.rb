# `is_a?` against a namespaced exception class answers true, also when
# another module holds a class of the same leaf name. is_a?, kind_of? and
# instance_of? agree with `rescue` and #ancestors. The shape comes from
# net/http, where Timeout::Error sits beside URI::Error.
module A
  class Error < StandardError; end
  class Sub < Error; end
end

module B
  class Error < RuntimeError; end
  class Sub < Error; end
end

a = A::Sub.new("x")
b = B::Sub.new("x")

# Each answers its own namespace's parent...
p a.is_a?(A::Error)
p b.is_a?(B::Error)
# ...and not the other one's, which shares the leaf name.
p a.is_a?(B::Error)
p b.is_a?(A::Error)

# The builtin grandparents still answer, and they differ between the two.
p a.is_a?(StandardError)
p b.is_a?(RuntimeError)
p a.is_a?(RuntimeError)

# instance_of? goes through the same name, and is exact.
p a.instance_of?(A::Sub)
p a.instance_of?(A::Error)

# ancestors was never wrong; pinned so the two cannot drift apart.
p A::Sub.ancestors.take(3).map(&:to_s)
p B::Sub.ancestors.take(3).map(&:to_s)

# rescue was never wrong either.
begin
  raise A::Sub, "boom"
rescue B::Error
  puts "WRONG namespace"
rescue A::Error => e
  puts "rescued: #{e.class}"
end
