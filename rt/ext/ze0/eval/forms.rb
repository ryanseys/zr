# frozen_string_literal: true

# The eval forms that take a string of ruby, over the compiler the
# program carries. Each one compiles the string and runs it under a self
# and a cref of its own; a program that names no eval keeps the
# block-only builtins these stand over.

module Kernel
  # Ruby run where this call stands: under the self and the cref of the
  # frame that asked, which is what an eval with no binding gets.
  def eval(source, binding = nil, file = nil, line = 1)
    unless binding.nil?
      raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)" unless binding.is_a?(Binding)

      code = Ze0::Eval.current.compile(source, file || Primitive.zr_eval_source_name, line, Primitive.zr_binding_scopes(binding), Primitive.zr_binding_in_method(binding))
      return Primitive.zr_binding_run(code, binding)
    end
    code = Ze0::Eval.current.compile(source, file || Primitive.zr_eval_source_name, line, Primitive.zr_eval_scopes, Primitive.zr_eval_in_method)
    Primitive.zr_eval_run(code, Primitive.zr_eval_self, Primitive.zr_eval_cref, Primitive.zr_eval_env)
  end
end

class Module
  # The module is the self and the definee, and a lexical scope on top
  # of the one the call stands in.
  def class_eval(*args, &block)
    if block
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)" unless args.empty?

      return class_exec(self, &block)
    end
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless (1..3).cover?(args.size)

    code = Ze0::Eval.current.compile(args[0], args[1] || Primitive.zr_eval_source_name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_in_method)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_under(self, Primitive.zr_eval_cref), Primitive.zr_eval_env)
  end

  alias module_eval class_eval
end

class BasicObject
  # The object is the self, and its singleton class is the definee, so a
  # `def` in the string is a method of that object alone.
  def instance_eval(*args, &block)
    if block
      unless args.empty?
        ::Kernel.raise ::ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)"
      end

      return instance_exec(self, &block)
    end
    unless (1..3).cover?(args.size)
      ::Kernel.raise ::ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)"
    end

    code = ::Ze0::Eval.current.compile(args[0], args[1] || Primitive.zr_eval_source_name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_in_method)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_under(Primitive.zr_eval_class_of(self), Primitive.zr_eval_cref), Primitive.zr_eval_env)
  end
end
