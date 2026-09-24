# frozen_string_literal: true

# `continuation`: callcc, and the Continuation a call goes back
# through, over the kernel's copy of the machine stack
# (runtime/kernel/continuation.rb).
# Init_continuation warns as it loads, naming the extension's own file.
warn "#{__FILE__}: warning: callcc is obsolete; use Fiber instead"

class Continuation
  class << self
    undef_method :new
  end

  # The callcc that made this one answers `args`: nil for none, the one,
  # or all of them in an Array.
  def call(*args)
    raise RuntimeError, "continuation called across threads" unless Primitive.zr_hidden_get(self, :__thread__).equal?(Thread.current)
    raise RuntimeError, "continuation called across fiber" unless Primitive.zr_hidden_get(self, :__fiber__).equal?(Fiber.current)

    Primitive.zr_hidden_set(self, :__value__, args.size <= 1 ? args.first : args)
    Primitive.zr_cont_resume(self)
  end
  alias [] call
end

module Kernel
  private

  def callcc
    continuation = Primitive.zr_class_build(Continuation)
    Primitive.zr_hidden_set(continuation, :__thread__, Thread.current)
    return Primitive.zr_hidden_get(continuation, :__value__) if Primitive.zr_cont_capture(continuation)

    yield continuation
  end
end
