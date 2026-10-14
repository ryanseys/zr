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
      Zr::Eval::Arguments.binding!(binding)
      name = file || Primitive.zr_eval_source_name
      using = Primitive.zr_binding_using_m(binding)
      code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(binding), Primitive.zr_binding_parameters(binding),
                                      using: using)
      Primitive.zr_trace_script_compiled(source, name, line)
      return Binding.send(:run_using, code, binding, using)
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
    using = Primitive.zr_binding_using_m(self)
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_binding_scopes(self), Primitive.zr_binding_parameters(self),
                                    using: using)
    Primitive.zr_trace_script_compiled(source, name, line)
    Binding.send(:run_using, code, self, using)
  end

  # Runs `code` in `binding`, which started under the `using` entry
  # `using`. A `using` at the toplevel of the string stays in the Binding,
  # as it changes the Binding's cref in ruby, so the next eval in it sees
  # the refinement, and so does the rest of a toplevel that it runs in.
  def self.run_using(code, binding, using)
    Primitive.attr! :hidden
    result = Primitive.zr_binding_run(code, binding)
    if code[5] && code[5] != using
      Primitive.zr_hidden_set(binding, :__using__, code[5])
      Primitive.zr_using_toplevel_m(binding, code[5])
    end
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
    source, file, line = Zr::Eval::Arguments.under(args)
    # The string runs under the refinements of the call site.
    using = Primitive.zr_eval_using
    name = file || Primitive.zr_eval_source_name
    code = Zr::Eval.current.compile(source, name, line, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters, using: using)
    Primitive.zr_trace_script_compiled(source, name, line)
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
    source, file, line = ::Zr::Eval::Arguments.under(args)
    using = Primitive.zr_eval_using
    name = file || Primitive.zr_eval_source_name
    code = ::Zr::Eval.current.compile(source, name, line, Primitive.zr_eval_scopes, Primitive.zr_eval_parameters, using: using)
    Primitive.zr_trace_script_compiled(source, name, line)
    Primitive.zr_eval_run(code, self, Primitive.zr_eval_cref_lazy(self, Primitive.zr_eval_cref), Primitive.zr_eval_env, Primitive.zr_eval_block)
  end
end
