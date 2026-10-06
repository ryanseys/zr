# Float reads text the way rb_cstr_to_dbl does: when the number has an
# underscore or text after it, its mantissa keeps at most sixty
# characters. Float#quo sends `/` under a guard, so a `/` aliased to
# quo raises NameError.
p Float(([1] * 10000).join).infinite?
p Float(([1] * 10000).join("_"))
p Float(([1] * 70).join("_") + ".5e3")
p Float(("1" * 70) + " ")
p (("1" * 70) + "x").to_f
p ("0" * 80 + "1_5").to_f
p Float("-" + "0" * 80 + "1_5")
p "1_1_1".to_f
class Float
  $VERBOSE = nil
  alias / quo
end
begin
  1.0 / 2.0
rescue NameError => e
  p [e.class, e.message, e.name]
end
