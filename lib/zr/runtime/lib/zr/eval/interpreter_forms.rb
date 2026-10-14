# frozen_string_literal: true

# The eval forms that take a string of ruby, over the tree-walking
# interpreter that a program includes where it cannot write machine code
# (lib/zr/eval/interpreter.rb). Each one gives the interpreter the scope of the
# calling frame, the self for the string and the lexical scope that its
# constants read. The block forms are the ones that every program keeps,
# and are here without changes.

module Kernel
  # Ruby run at the position of this call: over the locals and under the
  # cref of the calling frame, with the receiver as self.
  def eval(source, binding = nil, file = nil, line = 1)
    unless binding.nil?
      Zr::Eval::Arguments.binding!(binding)
      name = file || Primitive.zr_eval_source_name
      Primitive.zr_trace_script_compiled(source, name, line)
      return Zr::Eval::Interpreter.evaluate(source, binding, file: name, line: line, self_: Primitive.zr_binding_receiver(binding),
                                                             cref: Primitive.zr_binding_cref(binding), block: nil, add: true)
    end
    name = file || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(source, name, line)
    # A copy of the cref, as the compiler's form gives (forms.rb).
    Zr::Eval::Interpreter.evaluate(source, Primitive.zr_local_binding, file: name, line: line, self_: self,
                                                                       cref: Primitive.zr_cref_dup(Primitive.zr_eval_cref), block: Primitive.zr_eval_block)
  end

  # Public where it is called on Kernel itself, as the compiler's form
  # is: the stub that this method replaces left a copy of its own.
  module_function :eval
end

class Binding
  # Ruby run in this binding's scope, as Kernel#eval given it runs.
  def eval(source, file = nil, line = 1)
    name = file || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(source, name, line)
    Zr::Eval::Interpreter.evaluate(source, self, file: name, line: line, self_: Primitive.zr_binding_receiver(self),
                                                 cref: Primitive.zr_binding_cref(self), block: nil, add: true)
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
    source, file, line = Zr::Eval::Arguments.under(args)
    name = file || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(source, name, line)
    Zr::Eval::Interpreter.evaluate(source, Primitive.zr_local_binding, file: name, line: line, self_: self,
                                                                       cref: Primitive.zr_eval_cref_under(self, Primitive.zr_eval_cref), block: Primitive.zr_eval_block)
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
    name = file || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(source, name, line)
    # The singleton class is made when the code first needs it, and a
    # value that has none reads class variables farther out.
    ::Zr::Eval::Interpreter.evaluate(source, Primitive.zr_local_binding, file: name, line: line, self_: self,
                                                                         cref: Primitive.zr_eval_cref_lazy(self, Primitive.zr_eval_cref),
                                                                         block: Primitive.zr_eval_block)
  end
end
