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

# nil / bool into Integer slots ("from nil to integer" wording)

begin
  p([10, 20, 30].take(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p([10, 20, 30].rotate(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p([10, 20, 30].delete_at(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p([10, 20, 30].each_cons(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p((1..9).first(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p("ab" * nil)
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p("ab".center(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p(3.4.round(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p(5.to_s(nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p(Integer("5", nil))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p(:abc[nil])
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p([1, 2].fill(0, false))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end

