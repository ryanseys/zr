# An implicit conversion (to_ary, to_str, to_hash) that the value defines
# must give the type: nil too, which raises "X#to_hash gives nil". A value
# without the method raises "no implicit conversion". Methods that only
# try a conversion (Array(), flatten, a splat) take nil as no conversion.
class NilConv
  def to_ary = nil
  def to_str = nil
  def to_hash = nil
  def to_s = "nc"
  def inspect = "nc"
end
nc = NilConv.new

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue TypeError, ArgumentError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

t("Array#replace") { [].replace(nc) }
t("Array#product") { [1].product(nc) }
t("Array#transpose") { [nc].transpose }
t("Array#concat") { [].concat(nc) }
t("Array#+") { [] + nc }
t("Array#zip") { [1].zip(nc) }
t("Array#zip none") { [].zip(nc) }
t("Hash#merge!") { {}.merge!(nc) }
t("Hash#update") { {}.update({ c: 3 }, nc) }
t("Hash#merge") { {}.merge(nc) }
t("Hash#replace") { {}.replace(nc) }
t("Hash#transform_keys") { { a: 1 }.transform_keys(nc) }
t("tally_by") { [1].tally(nc) }
t("String#+") { "a" + nc }
t("String#scrub") { "\xff".scrub(nc) }
t("encode replace") { "a".encode("UTF-16", replace: nc) }
t("const_get") { Object.const_get(nc) }
t("Hash()") { Hash(nc) }
t("Hash(true)") { Hash(true) }
t("Hash(1)") { Hash(1) }
t("**") { { **nc } }
t("Array()") { Array(nc) }
t("String()") { String(nc) }
t("flatten") { [nc].flatten }
t("splat") { [*nc] }
t("multiple assign") { a, b = nc; [a, b] }

class Plain; end
t("no method") { {}.merge!(Plain.new) }
t("no method ary") { [] + Plain.new }
class Wrong
  def to_ary = 5
  def to_hash = "h"
end
t("wrong ary") { [].replace(Wrong.new) }
t("wrong hash") { {}.merge!(Wrong.new) }
