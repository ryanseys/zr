# A run-time `alias_method` on Kernel whose source is a BUILTIN row landed
# where an ordinary receiver could reach it and nowhere a Class or Module
# receiver looks -- while `respond_to?` answered true for both, so the
# disagreement was between two of zr's own tables.
#
# rubygems' `kernel_require.rb` is exactly this shape
# (`alias_method :gem_original_require, :require`), and it is required at run
# time, so `zr gem install` died with "undefined method
# 'gem_original_require' for class Gem::Net::HTTP".
#
# The require must be COMPUTED: spliced through `-I` the alias and its callers
# compile into one stream and the frozen registry answers.

$LOAD_PATH.unshift File.expand_path(
  "runtime_alias/lib", __dir__
)
feature = "kernel_patch"
require feature

class Widget; end
module Trait; end
anon = Module.new
obj = Object.new

p Widget.respond_to?(:zr_orig_frozen, true)
[Widget, Trait, anon, (class << obj; self; end), obj].each do |recv|
  p recv.send(:zr_orig_frozen)
end
