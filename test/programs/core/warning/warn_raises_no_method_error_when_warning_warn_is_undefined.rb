# With Warning#warn undefined, Kernel#warn raises NoMethodError, as
# rb_funcall does; a warning of a disabled category is not emitted at all
# (test_exception.rb's test_undef_Warning_warn).
Warning.undef_method(:warn)
begin
  warn ""
rescue NoMethodError => e
  p [e.class, e.message]
end
begin
  warn "x", category: :deprecated
rescue NoMethodError => e
  p [e.class, e.message]
end
