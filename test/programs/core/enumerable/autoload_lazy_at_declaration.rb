# An `autoload` target does not load BEFORE the statement holding it:
# differ.rb calls a singleton method this module body installs a few
# statements earlier (rspec-support's exact shape).
#
# The target runs at the constant's first ACCESS, as CRuby's does --
# see `autoload_is_lazy.rb`.
module Outer
  module Foo
    puts "body-1"
    def self.tag(x) = "tagged #{x}"
    autoload :Differ, "#{__dir__}/autoload_lazy/differ"
    puts "body-2"
  end
end
puts Outer::Foo::Differ.origin
