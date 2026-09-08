# frozen_string_literal: true

# An `autoload` target the compile can NAME becomes a lazily linked unit
# and the declaration stays a real call, so the file runs when the
# constant is first read -- CRuby's own order. Three spellings resolve
# here: a plain feature, `"#{__dir__}/..."` and
# `File.expand_path("...", __dir__)`.
#
# A superclass clause is a read too, and so is the receiver of a `Foo.new`
# the compile constructs directly.

module Paths
  autoload :Widget, "#{__dir__}/autoload_paths/target"
end

autoload :PathBase, File.expand_path("autoload_paths/base", __dir__)

puts "before the read"
p Paths.autoload?(:Widget) != nil
p Paths::Widget.new.kind
p Paths.autoload?(:Widget)

class PathSub < PathBase
end
p PathSub.new.limit
p PathSub.superclass
__END__
before the read
true
target ran
:widget
nil
base ran
7
PathBase
