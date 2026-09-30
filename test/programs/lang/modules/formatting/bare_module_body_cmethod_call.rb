# Bare (receiverless) class-method call in a module/class body must propagate
# the callee's return type to the call expression.
#
# `def self.mk` returns a Hash; called bare as `mk` (not `M.mk`) in the
# module body and passed as an argument, so `take(mk)` gets a
# Hash[String,String].

module M
  def self.mk
    h = {"" => ""}
    h.delete("")
    h["a"] = "1"
    h
  end

  class R
    def take(opts)
      n = 0
      opts.each { |k, v| n = n + 1 }
      n
    end
  end

  COUNT = R.new.take(mk)   # bare `mk`; result must be Hash[String,String]
end

puts M::COUNT.to_s         # 1
