# A Bignum takes a Float divisor as a Float (big_modulo with to_f), so
# ruby's ZeroDivisionError for a Float zero comes from 'Float#%', with
# 'Integer#%' or 'Integer#modulo' after it. A Fixnum raises from its own
# frame (test/programs/core/file/a_bad_path_names_only_the_method_that_was_called_in_the_backtrace.rb).
def labels
  p yield
rescue ZeroDivisionError => e
  p e.backtrace_locations.map(&:label).take_while { |l| !l.start_with?("block") }
end

big = 2**70
labels { big % 0.0 }
labels { big.modulo(0.0) }
labels { (-big) % -0.0 }
labels { big.divmod(0.0) }
labels { big.div(0.0) }
labels { big % 0 }
labels { big.modulo(0) }
labels { 5 % 0.0 }
labels { 5.modulo(0.0) }

# The values a Float divisor gives, which are Float#%'s.
p big % 2.5, big.modulo(-2.5), (-big) % 3.0, big % Float::INFINITY, (-big) % Float::INFINITY
p (big % Float::NAN).nan?, big.modulo(1e300), big % 1e-300, (2**1100 % 7.5).nan?
p big % 7, big.modulo(-7), big % (2**65), big % 2r, big % 2.5r
