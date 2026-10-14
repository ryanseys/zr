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
      raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)" unless binding.is_a?(Binding)

      name = file || Primitive.zr_eval_source_name
      Primitive.zr_trace_script_compiled(source, name, line)
      return Zr::Eval.current.run(source, name, line, binding,
                                   Primitive.zr_binding_receiver(binding), Primitive.zr_binding_cref(binding), nil, add: true)
    end
    name = file || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(source, name, line)
    # A copy of the cref, as the compiler's form gives (forms.rb).
    Zr::Eval.current.run(source, name, line, Primitive.zr_local_binding,
                          self, Primitive.zr_cref_dup(Primitive.zr_eval_cref), Primitive.zr_eval_block)
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
    Zr::Eval.current.run(source, name, line, self,
                          Primitive.zr_binding_receiver(self), Primitive.zr_binding_cref(self), nil, add: true)
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

    # eval_under: the source and the file name are Strings, and the
    # line is a C int, as the compiler's form converts them (forms.rb).
    args[0] = Primitive.zr_str_operand(args[0])
    args[1] = Primitive.zr_str_operand(args[1]) unless args[1].nil?
    args[2] = Primitive.zr_index_operand_m(args[2]) unless args[2].nil?
    name = args[1] || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(args[0], name, args[2] || 1)
    Zr::Eval.current.run(args[0], name, args[2] || 1, Primitive.zr_local_binding,
                          self, Primitive.zr_eval_cref_under(self, Primitive.zr_eval_cref), Primitive.zr_eval_block)
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

    # eval_under: the source and the file name are Strings, and the
    # line is a C int, as the compiler's form converts them (forms.rb).
    args[0] = Primitive.zr_str_operand(args[0])
    args[1] = Primitive.zr_str_operand(args[1]) unless args[1].nil?
    args[2] = Primitive.zr_index_operand_m(args[2]) unless args[2].nil?
    # The singleton class is made when the code first needs it, and a
    # value that has none reads class variables farther out.
    name = args[1] || Primitive.zr_eval_source_name
    Primitive.zr_trace_script_compiled(args[0], name, args[2] || 1)
    ::Zr::Eval.current.run(args[0], name, args[2] || 1, Primitive.zr_local_binding,
                            self, Primitive.zr_eval_cref_lazy(self, Primitive.zr_eval_cref), Primitive.zr_eval_block)
  end
end
