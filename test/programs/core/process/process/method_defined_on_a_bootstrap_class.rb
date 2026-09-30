# `method_defined?` on an EXCEPTION class asks at run time, because the
# compiler cannot see the rows those classes have.
#
# The exception hierarchy is written in ruby but carries hand-registered
# NATIVE rows. They are not compiled `def`s, and they reach no class
# header. So a compile-time answer would be a wrong FALSE about rows the
# class really has.
#
# `error_highlight`'s core_ext gates its whole API on
# `Exception.method_defined?(:detailed_message)`. A false answer picks the
# pre-3.2 `to_s` branch of the library.
module Probe
  ANSWER = if Exception.method_defined?(:detailed_message)
    :folded_or_asked_true
  else
    :answered_false
  end
end

p Probe::ANSWER
p Exception.method_defined?(:detailed_message)
p Exception.method_defined?(:full_message)
p Exception.method_defined?(:no_such_row_anywhere)
p NameError.method_defined?(:name)
p NoMethodError.method_defined?(:private_call?)
p StandardError.method_defined?(:backtrace_locations)

# A class body asks in its own scope, with an implicit receiver.
class Custom < StandardError
  RESULT = [
    method_defined?(:detailed_message),
    method_defined?(:message),
    method_defined?(:nope),
  ]
end
p Custom::RESULT
