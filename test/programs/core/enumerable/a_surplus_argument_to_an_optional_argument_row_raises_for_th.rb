# The Enumerable/Array rows that take an OPTIONAL argument must still count
# what they were given: a surplus one is `wrong number of arguments`, not a
# conversion error on the first, and not silently ignored.
#
# The message names the full range of the method (`count` takes 0..1).
# `tally(:x)` and `zip()` are controls with a correct argument count.
rows = {
  "tally(1, 2)" => -> { [1, 2].tally(1, 2) },
  "tally(:x)" => -> { [1, 2].tally(:x) },
  "tally({}, 2)" => -> { [1, 2].tally({}, 2) },
  "sum(0, 1)" => -> { [1].sum(0, 1) },
  "min(1, 2)" => -> { [1].min(1, 2) },
  "max(1, 2)" => -> { [1].max(1, 2) },
  "first(1, 2)" => -> { [1].first(1, 2) },
  "uniq(1)" => -> { [1].uniq(1) },
  "flatten(1, 2)" => -> { [1].flatten(1, 2) },
  "count(1, 2)" => -> { [1].count(1, 2) },
  "zip()" => -> { [1].zip },
  "group_by(1)" => -> { [1].group_by(1) { |x| x } },
  "each_slice(1, 2)" => -> { [1].each_slice(1, 2) { break } },
  "each_cons(1, 2)" => -> { [1].each_cons(1, 2) { break } },
}
rows.each do |name, fn|
  r = begin
    v = fn.call
    "ok #{v.inspect}"
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{name}\t#{r}"
end
