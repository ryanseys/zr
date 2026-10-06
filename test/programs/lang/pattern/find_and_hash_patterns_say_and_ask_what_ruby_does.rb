# A find pattern on a too short subject fails on its length, and a hash
# pattern asks deconstruct_keys for its keys: none for `{**}`, every one
# (nil) for `{}` and `{**rest}`.
def t
  yield
rescue NoMatchingPatternError => e
  p e.message
end
t { [] => [*, _, *] }
t { [0] => [*, 1, *] }
t { 0 => [*, _, *] }

class C
  class << self
    attr_accessor :keys
  end

  def initialize(h) = @h = h

  def deconstruct_keys(keys)
    C.keys = keys
    @h
  end
end
def keys_for(value)
  C.keys = :unset
  yield value
  p C.keys
end
keys_for(C.new({})) { |v| case v; in {} then nil; end }
keys_for(C.new({ a: 0, b: 0 })) { |v| case v; in { a: 0, b: } then nil; end }
keys_for(C.new({ a: 0, b: 0 })) { |v| case v; in { a: 0, ** } then nil; end }
keys_for(C.new({ a: 0, b: 0 })) { |v| case v; in { a: 0, **r } then nil; end }
keys_for(C.new({ a: 0 })) { |v| case v; in { ** } then nil; end }
