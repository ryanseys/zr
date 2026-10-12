# The prelude's Binding#irb is a stand-in that loads irb. Requiring irb
# by hand is that same load, so the method a program calls afterwards is
# irb's own and not the one it started with.
before = Binding.instance_method(:irb)
require "irb"
p IRB::VERSION.match?(/\A\d+\.\d+\.\d+/)
p Binding.instance_method(:irb) == before
p Binding.private_method_defined?(:irb)
