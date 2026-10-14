# frozen_string_literal: true

# The checks and conversions of the arguments of the eval forms that take
# a string, as eval.c makes them. The forms of both back ends share them
# (forms.rb, interpreter_forms.rb). The primitives that read the calling
# frame stay in each form: here they would read this module's frame.
# Each method is hidden, so an error's backtrace starts at the form, as
# ruby's does.

module Zr
  class Eval
    module Arguments
      # `binding`, eval's second argument, which must be a Binding.
      def self.binding!(binding)
        Primitive.attr! :hidden
        return binding if binding.is_a?(Binding)

        raise TypeError, "wrong argument type #{conversion_name(binding)} (expected binding)"
      end

      # eval_under's arguments, for class_eval and instance_eval with no
      # block: 1 to 3 of them, the source and the file as Strings, and the
      # line as a C int. Returns `[source, file, line]`, with nil for a
      # file that is not given and 1 for a line.
      def self.under(args)
        Primitive.attr! :hidden
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..3)" unless (1..3).cover?(args.size)

        source, file, line = args
        [Primitive.zr_str_operand(source), file.nil? ? nil : Primitive.zr_str_operand(file),
         line.nil? ? 1 : Primitive.zr_index_operand_m(line)]
      end
    end
  end
end
