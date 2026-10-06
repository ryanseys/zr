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
    using = Primitive.zr_eval_using
    unless binding.nil?
      raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)" unless binding.is_a?(Binding)

      name = file || Primitive.zr_eval_source_name
      code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(binding), Primitive.zr_binding_parameters(binding),
                                      using: Primitive.zr_hidden_get(binding, :__using__))
      Primitive.zr_trace_script_compiled(source, name, line)
      return Binding.send(:run_using, code, binding)
    end
    name = file || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters, using: using)
    Primitive.zr_trace_script_compiled(source, name, line)
    Primitive.zr_eval_run(code, self, Primitive.zr_cref_dup(Primitive.zr_eval_cref), Primitive.zr_eval_env, Primitive.zr_eval_block)
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
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(self), Primitive.zr_binding_parameters(self),
                                    using: Primitive.zr_hidden_get(self, :__using__))
    Primitive.zr_trace_script_compiled(source, name, line)
    Binding.send(:run_using, code, self)
  end

  # Runs `code` in `binding`. A `using` at the toplevel of the string
  # stays in the Binding, as it changes the Binding's cref in ruby, so the
  # next eval in it sees the refinement.
  def self.run_using(code, binding)
    Primitive.attr! :hidden
    result = Primitive.zr_binding_run(code, binding)
    Primitive.zr_hidden_set(binding, :__using__, code[5]) if code[5]
    result
  end
  private_class_method :run_using
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

    # The string runs under the refinements of the call site.
    using = Primitive.zr_eval_using
    # eval_under: the source and the file name are Strings, and the
    # line is a C int.
    args[0] = Primitive.zr_str_operand(args[0])
    args[1] = Primitive.zr_str_operand(args[1]) unless args[1].nil?
    args[2] = Primitive.zr_index_operand_m(args[2]) unless args[2].nil?
    name = args[1] || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(args[0], name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters, using: using)
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

    using = Primitive.zr_eval_using
    # eval_under: the source and the file name are Strings, and the
    # line is a C int.
    args[0] = Primitive.zr_str_operand(args[0])
    args[1] = Primitive.zr_str_operand(args[1]) unless args[1].nil?
    args[2] = Primitive.zr_index_operand_m(args[2]) unless args[2].nil?
    name = args[1] || Primitive.zr_eval_source_name
    code = ::Zr::Eval.current.compile(args[0], name, args[2] || 1, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters, using: using)
    Primitive.zr_trace_script_compiled(args[0], name, args[2] || 1)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_lazy(self, Primitive.zr_eval_cref), Primitive.zr_eval_env, Primitive.zr_eval_block)
  end
end
