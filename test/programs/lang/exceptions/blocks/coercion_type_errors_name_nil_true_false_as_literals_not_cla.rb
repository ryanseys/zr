# CRuby renders nil/true/false in a coercion TypeError as those words, not
# `NilClass`/`TrueClass`/`FalseClass`; every other object uses its class
# name (`Integer`, `Symbol`).

def msg
  yield
rescue TypeError => e
  puts e.message
end
msg { "" + nil }
msg { "" + true }
msg { "" + false }
msg { "" + 1 }
msg { "" + :s }
msg { Float(nil) }
msg { Integer(true) }
# A non-class target phrase ("an exact number") keeps the CLASS name,
# even for nil -- the value-name rule is specific to class targets.
msg { Time.at(nil) }
