# An eval of a source that is not ASCII compatible raises "invalid source
# encoding", and the source locations of two methods from one file give
# the same frozen path, as CRuby gives an iseq's path (test_eval.rb's
# test_eval_ascii_incompatible and test_eval_location_fstring).
%w[UTF-16BE UTF-16LE UTF-32BE UTF-32LE].each do |enc|
  eval("__ENCODING__".encode(enc))
  p :no_error
rescue ArgumentError => e
  p [e.class, e.message]
end
o = Object.new
o.instance_eval "def foo() end", "generated code"
o.instance_eval "def bar() end", "generated code"
a, b = o.method(:foo).source_location[0], o.method(:bar).source_location[0]
p a.equal?(b), a.frozen?
def m1; end
def m2; end
p method(:m1).source_location[0].equal?(method(:m2).source_location[0]), proc {}.source_location[0].frozen?, binding.source_location[0].frozen?, __FILE__.frozen?
