# ruby labels the frame of a C method that an alias reached with the
# alias's owner when the method came from a class (rb_alias makes the
# alias's class the entry's owner): 'Klass.<=>', 'A#fetch'. An alias of a
# module's method keeps the module. zr labels a frame from its function's
# own owner, and a frame does not record which method entry the call
# went through, so it shows 'Module#<=>' and 'Array#fetch'. Found by
# zr-dev fuzz.
def label
  yield
rescue StandardError => e
  p e.backtrace_locations.first.label
end

class Klass
  singleton_class.alias_method :nickname, :<=>
end
label { Klass.nickname }

class A < Array
  alias x fetch
end
label { A.new.x(9) }

class H < Hash
  alias_method :get, :fetch
end
label { H.new.get(:k) }

class B
  include Comparable
  alias_method :btw, :between?
end
label { B.new.btw }

class String
  alias_method :ss, :sub
end
label { "".ss }
