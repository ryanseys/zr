# frozen_string_literal: true

# The eval forms that take a string of ruby, over the compiler that the
# program links in. Each one compiles the string and runs it under a self
# and a cref of its own. A program that does not call eval by name keeps
# the block-only builtins that these replace.

module Kernel
  # Ruby run at the position of this call: over the locals and under the
  # cref of the calling frame, as an eval with no binding gets. The
  # receiver is self, which is that frame's own self unless a `send`
  # gave another.
  def eval(source, binding = nil, file = nil, line = 1)
    unless binding.nil?
      raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)" unless binding.is_a?(Binding)

      name = file || Primitive.zr_eval_source_name
      code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(binding), Primitive.zr_binding_parameters(binding))
      Primitive.zr_trace_script_compiled(source, name, line)
      return Primitive.zr_binding_run(code, binding)
    end
    name = file || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters)
    Primitive.zr_trace_script_compiled(source, name, line)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref, Primitive.zr_eval_env, Primitive.zr_eval_block)
  end

  # As in ruby: private where it is written, public where it is
  # called on Kernel itself. `module_function` makes the second
  # copy, and the copy must be made here, because the stub that this
  # method replaces left a copy of its own.
  module_function :eval
end

class Binding
  # Ruby run in this binding's scope, as Kernel#eval given it runs.
  def eval(source, file = nil, line = 1)
    name = file || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(self), Primitive.zr_binding_parameters(self))
    Primitive.zr_trace_script_compiled(source, name, line)
    Primitive.zr_binding_run(code, self)
  end
end

class Module
  # The module is the self and the definee, and a lexical scope on top
  # of the scope of the call.
  def class_eval(*args, &block)
    if block
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)" unless args.empty?

      return class_exec(self, &block)
    end
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless (1..3).cover?(args.size)

    name = args[1] || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(args[0], name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters)
    Primitive.zr_trace_script_compiled(args[0], name, args[2] || 1)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_under(self, Primitive.zr_eval_cref), Primitive.zr_eval_env, Primitive.zr_eval_block)
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

    name = args[1] || Primitive.zr_eval_source_name
    code = ::Zr::Eval.current.compile(args[0], name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters)
    Primitive.zr_trace_script_compiled(args[0], name, args[2] || 1)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_under(Primitive.zr_eval_class_of(self), Primitive.zr_eval_cref), Primitive.zr_eval_env, Primitive.zr_eval_block)
  end
end
