# Hash[] names nil, true and false in its error, two Hashes that differ only
# by compare_by_identity are not equal unless empty, and transform_keys takes
# a mapping that must be a Hash when given, nil too.
$stdout.sync = true
begin; Hash[[1,2], nil]; rescue => e; p e; end
begin; Hash[[[1,2], nil]]; rescue => e; p e; end
begin; Hash[[[1,2], 5]]; rescue => e; p e; end
a = {1=>2}; b = {1=>2}.compare_by_identity; p a == b, b == a, a.eql?(b), b.eql?(a)
p({} == {}.compare_by_identity, {}.compare_by_identity == {}.compare_by_identity)
begin; {a: 1}.transform_keys(nil); rescue => e; p e; end
begin; {a: 1}.transform_keys!(nil); rescue => e; p e; end
p({a: 1, b: 2}.transform_keys({a: :x}), {a: 1}.transform_keys({a: :x}) { |k| k.to_s })
begin; Hash[[true]]; rescue => e; p e; end
begin; Hash[[:a]]; rescue => e; p e; end
b = {1 => 2}.compare_by_identity
p b == b.dup, b.hash == {1 => 2}.hash
