# A user-defined `class EE < Exception` instance works correctly
# wherever it is passed, even through indirect construction and
# yielding across module and class boundaries (the shape used by the
# timeout gem's `ExitException`).

module T
  class EE < Exception
  end
  class Er < RuntimeError
    def self.go(m)
      exc = EE.new(m)
      yield exc
    end
  end
end
T::Er.go("x") { |e| puts e.class; puts e.message }
