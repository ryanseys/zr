# frozen_string_literal: true

# The eval forms that take a string of ruby, over the tree-walking
# interpreter that a program includes where it cannot write machine code
# (lib/zr/eval/walk.rb). Each one gives the interpreter the scope of the
# calling frame, the self for the string and the lexical scope that its
# constants read. The block forms are the ones that every program keeps,
# and are here without changes.

module Kernel
  # Ruby run where this call stands: over the locals and under the cref
  # of the frame that asked, with the receiver as self.
  def eval(source, binding = nil, file = nil, line = 1)
    unless binding.nil?
      raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)" unless binding.is_a?(Binding)

      return Zr::Eval.current.run(source, file || Primitive.zr_eval_source_name, line, binding,
                                   Primitive.zr_binding_receiver(binding), Primitive.zr_binding_cref(binding), nil, true)
    end
    Zr::Eval.current.run(source, file || Primitive.zr_eval_source_name, line, Primitive.zr_binding,
                          self, Primitive.zr_eval_cref, Primitive.zr_eval_block)
  end
end

class Binding
  # Ruby run in this binding's scope, as Kernel#eval given it runs.
  def eval(source, file = nil, line = 1)
    Zr::Eval.current.run(source, file || Primitive.zr_eval_source_name, line, self,
                          Primitive.zr_binding_receiver(self), Primitive.zr_binding_cref(self), nil, true)
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

    Zr::Eval.current.run(args[0], args[1] || Primitive.zr_eval_source_name, args[2] || 1, Primitive.zr_binding,
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

    ::Zr::Eval.current.run(args[0], args[1] || Primitive.zr_eval_source_name, args[2] || 1, Primitive.zr_binding,
                            self, Primitive.zr_eval_cref_under(Primitive.zr_eval_class_of(self), Primitive.zr_eval_cref),
                            Primitive.zr_eval_block)
  end
end
