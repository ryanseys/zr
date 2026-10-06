# CRuby's argument-conversion TypeErrors, message included.
#
# Four rules, each spelled where CRuby spells it: a `Check_Type` message
# (`wrong argument type X (expected Y)`) names `nil`/`true`/`false` as the
# VALUE rather than the class; `rb_num2long` says "no implicit conversion
# from nil to integer" where `rb_to_int` says "of nil into Integer";
# `StringScanner`'s pattern slot reads with `StringValue`, so its refusal
# is the STRING conversion's; and a rounding digit count, a radix and a
# random seed are conversions, never arithmetic coercions.
#
# A compile-time-known nil / true / false (or wrong-classed scalar) that
# enters a String- or Integer-typed slot of a builtin raises CRuby's
# TypeError, wording included. It does not become "" or 0. The slots that
# CRuby itself accepts nil in keep working.

# super(nil) into a builtin exception keeps CRuby's class-name default
class ConvE < StandardError
  def initialize; super(nil); end
end
p ConvE.new.message
