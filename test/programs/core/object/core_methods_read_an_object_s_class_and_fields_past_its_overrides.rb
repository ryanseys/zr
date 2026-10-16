# Core methods read what CRuby's C reads straight from the object:
# the frozen flag, the real class, the class's path, a range's fields
# and an exception's stored backtrace. A program's overrides of
# frozen?, class, to_s, begin, backtrace, name or singleton_class?
# never change their answers.
# rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
def t(label)
  print label, ": "
  p(yield.then { |v| v.is_a?(String) ? v.sub(/0x\h+/, "0x") : v })
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{e.class}: #{e.message.sub(/0x\h+/, "0x")}"
end
class M; def frozen? = true; end
t("dup frozen?") { M.new.dup.class }
class P; def class = String; end
t("dup class") { P.new.dup.instance_of?(P) }
t("clone class") { P.new.clone.instance_of?(P) }
class E < StandardError; def self.to_s = "Custom"; end
t("detailed") { E.new("boom").detailed_message }
t("full") { E.new("boom").full_message(highlight: false) }
class E2 < StandardError; def backtrace = [rand.to_s]; end
t("exc == bt") { E2.new("m") == E2.new("m") }
class E3 < StandardError; def class = RuntimeError; end
t("exc == class") { E3.new("m") == E3.new("m") }
t("exc == other") { E3.new("m") == RuntimeError.new("m") }
class R < Range; def begin = 99; end
t("range ==") { [(1..2) == R.new(1, 2), (1..2).eql?(R.new(1, 2))] }
o = Object.new
def o.is_a?(_k) = true
t("range == liar") { (1..2) == o }
class R2 < Range; def exclude_end? = true; def end = 5; end
t("range dup") { R2.new(1, 2).dup }
class F < File; def self.to_s = "X"; end
t("io inspect") { F.new("/dev/null").inspect }
Z = Object.new
def Z.is_a?(_k) = true
def Z.==(_o) = true
def Z.>(_o) = false
def Z.<(_o) = true
class V; include Comparable; def <=>(_o) = Z; end
t("comparable ==") { V.new == V.new }
t("comparable <") { V.new < V.new }
class C1; def self.singleton_class? = true; end
t("marshal singleton?") { Marshal.dump(C1).bytesize }
c = Class.new { def self.inspect = "Nice" }
t("marshal anon") { Marshal.dump(c.new) }
class C2; def marshal_dump = 1; def self.name = "Fake"; end
t("marshal_load missing") { Marshal.load(Marshal.dump(C2.new)) }
class C3; def _dump(_l) = ""; def self.name = "Fake"; end
t("_load missing") { Marshal.load(Marshal.dump(C3.new)) }
S = Struct.new(:a)
class S; def self.name = "Fake"; end
t("struct compat") { Marshal.load(Marshal.dump(S.new(1)).sub(":a".b, ":b".b)) }
t("conv inspect") { Class.new(Encoding::Converter) { def self.to_s = "X" }.new("UTF-8", "EUC-JP").inspect }
class Liar; def class = Integer; end
t("type error") { [1, 2].first(Liar.new) }
t("range step") { (1..2).step(Liar.new).to_a }
# rubocop:enable Lint/BinaryOperatorWithIdenticalOperands
