# frozen_string_literal: true

# A Binding names a scope: the locals it holds, the self it runs under
# and the lexical scope its constants read. It shares the scope's slots
# rather than copying them, so a write on either side is seen on both,
# and a local declared after the capture is already in it.
class Binding
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new
  end

  def receiver = Primitive.zr_binding_receiver(self)

  def source_location = [Primitive.zr_binding_file(self), Primitive.zr_binding_line(self)]

  def local_variables
    scopes.flatten.compact.uniq
  end

  def local_variable_defined?(name) = !place(symbol_name(name)).nil?

  def local_variable_get(name)
    name = symbol_name(name)
    at = place(name) or raise NameError, "local variable '#{name}' is not defined for #{inspect}"
    Primitive.zr_binding_get(self, at[0], at[1])
  end

  # A name no scope holds becomes the Binding's own, in a scope inside
  # the one it named, as ruby gives it.
  def local_variable_set(name, value)
    name = symbol_name(name)
    Primitive.zr_binding_add(self, name.to_s) unless place(name)
    at = place(name)
    Primitive.zr_binding_set(self, at[0], at[1], value)
  end

  # The eval road defines this again over the compiler the program
  # brought, as it does Kernel#eval.
  def eval(source, file = nil, line = 1) = Primitive.zr_unimplemented("eval reached in a program built without the compiler")

  def inspect = "#<Binding:0x#{format("%016x", object_id * 2)}>"

  alias to_s inspect

  private

  # The name of a local, as ruby takes one: a Symbol or a String.
  def symbol_name(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Symbol)
    return name.to_sym if name.is_a?(String)

    raise TypeError, "#{name.inspect} is not a symbol nor a string"
  end

  # `[depth, index]` of `name`, or nil where no scope holds it. A hidden
  # local of the lowering keeps its slot but takes no name.
  def place(name)
    Primitive.attr! :hidden
    scopes.each_with_index do |names, depth|
      i = names.index(name)
      return [depth, i] if i
    end
    nil
  end

  # The names each scope holds, innermost first, hidden ones dropped.
  def scopes
    Primitive.attr! :hidden
    Primitive.zr_binding_scopes(self).map { |names| names.map { |n| named?(n) ? n : nil } }
  end

  def named?(name)
    Primitive.attr! :hidden
    /\A[a-z_][A-Za-z0-9_]*\z/.match?(name.to_s)
  end
end

module Kernel
  # The scope this call stands in.
  def binding = Primitive.zr_binding

  # The names the caller's scope holds, which is what its Binding names.
  def local_variables = Primitive.zr_binding.local_variables
end
