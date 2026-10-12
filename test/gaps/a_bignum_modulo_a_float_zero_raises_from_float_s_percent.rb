# A Bignum takes a Float divisor as a Float (big_modulo with to_f), so
# ruby's ZeroDivisionError for a Float zero comes from 'Float#%', with
# 'Integer#%' or 'Integer#modulo' after it. zr's Float#% has no Ruby
# frame, so only the Integer frames show. A Fixnum raises from its own
# frame in both (test/programs/core/file/a_bad_path_names_only_the_method_that_was_called_in_the_backtrace.rb).
def labels
  yield
rescue ZeroDivisionError => e
  p e.backtrace_locations.map(&:label).take_while { |l| !l.start_with?("block") }
end

labels { (2**70) % 0.0 }
labels { (2**70).modulo(0.0) }
labels { (-2**70) % -0.0 }
