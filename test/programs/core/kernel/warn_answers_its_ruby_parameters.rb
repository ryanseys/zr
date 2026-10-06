# CRuby writes Kernel#warn in Ruby, so its parameters are the Ruby
# ones, not the `[[:rest]]` a method written in C answers. A library
# that checks for the category keyword (prism's polyfill does) must
# find it, or it prepends a wrapper to Kernel and Object.
p Kernel.instance_method(:warn).parameters
p Kernel.method(:warn).parameters
p Kernel.instance_method(:warn).arity
p Object.ancestors
p Kernel.instance_method(:puts).parameters
