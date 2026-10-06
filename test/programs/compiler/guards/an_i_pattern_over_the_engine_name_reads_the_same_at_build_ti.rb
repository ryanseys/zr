# A version gate is written against the NUMBER as often as against the string
# (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
# All three are as fixed for a whole-program target as the version strings the
# comparison folders already decide, and each one wraps a whole class in the
# corpus -- so a compiler that cannot decide it registers both arms and reports
# a superclass mismatch for a program ruby runs without complaint.

module Framework
  module VERSION
    MAJOR = 8
    MINOR = 1
    STRING = "8.1.0"
  end
end

if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
  class Adapter < Array
    def which = :current
  end
else
  class Adapter < String
    def which = :legacy
  end
end

# `/i` -- the spelling a jruby gate uses.
if RUBY_PLATFORM =~ /java/i
  class Vm < String
    def which = :jvm
  end
else
  class Vm < Array
    def which = :native
  end
end
p Vm.superclass
p Vm.new.which

