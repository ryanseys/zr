# frozen_string_literal: true

# Where every warning goes. A program overrides `Warning.warn` to catch
# them, and turns a category on or off with `Warning[]=`.
module Warning
  CATEGORIES = { deprecated: false, experimental: true, performance: false, strict_unused_block: false }
  private_constant :CATEGORIES

  def self.categories = CATEGORIES.keys

  def self.[](category) = CATEGORIES[category_name(category)]

  # A flag of any truth turns the category on; the reader gives true or
  # false.
  def self.[]=(category, flag)
    CATEGORIES[category_name(category)] = flag ? true : false
    Primitive.zr_warn_deprecated_set(flag ? true : false) if category == :deprecated
    flag
  end

  # rb_warning_s_warn: writes the message on $stderr, unless its
  # category is off.
  def warn(message, category: nil)
    unless message.is_a?(String)
      raise TypeError, "wrong argument type #{Warning.send(:type_name, message)} (expected String)"
    end
    raise Encoding::CompatibilityError, "ASCII incompatible encoding: #{message.encoding}" unless message.encoding.ascii_compatible?
    return nil unless category.nil? || Warning[category]

    $stderr.write(message)
    nil
  end

  # rb_warning_category_from_name: a Symbol that names a category.
  def self.category_name(category)
    Primitive.attr! :hidden
    raise TypeError, "wrong argument type #{type_name(category)} (expected Symbol)" unless category.is_a?(Symbol)
    raise ArgumentError, "unknown category: #{category}" unless CATEGORIES.key?(category)

    category
  end

  # The name Check_Type gives a value of the wrong type.
  def self.type_name(value)
    Primitive.attr! :hidden
    case value
    when nil, true, false then value.inspect
    else value.class.to_s
    end
  end

  # rb_warn_category: a Warning.warn that takes one argument gets the
  # text alone, else the text and its category. With no Warning.warn, the
  # call raises NoMethodError, as rb_funcall does.
  def self.emit(text, category)
    Primitive.attr! :hidden
    respond_to?(:warn, true) && method(:warn).arity == 1 ? warn(text) : warn(text, category: category)
  end

  # The runtime's own way in, for a warning it raises with a category.
  def self.deprecated(message)
    Primitive.attr! :hidden
    return nil if $VERBOSE.nil? || !self[:deprecated]

    emit("#{Primitive.zr_warn_position}warning: #{message}\n", :deprecated)
  end

  # The same entry point for a feature that ruby calls experimental. The
  # notice gives the line that reached it, as ruby's does.
  def self.experimental(message)
    Primitive.attr! :hidden
    return nil if $VERBOSE.nil? || !self[:experimental]

    emit("#{Primitive.zr_warn_position}warning: #{message}\n", :experimental)
  end

  # The runtime's way in when a program writes over one of the core's
  # basic operators (lib/zr/runtime/kernel/class.rb, zr_warn_operator).
  def self.operator_redefined(klass, name)
    Primitive.attr! :hidden
    return nil unless self[:performance]

    emit("#{Primitive.zr_warn_position}warning: Redefining '#{klass}##{name}' disables interpreter and JIT optimizations\n", :performance)
  end

  # The names of ruby's own methods written in Ruby that use their block.
  # Outside the strict_unused_block category, ruby does not warn for a
  # method with one of these names (iseq_set_use_block).
  CORE_BLOCK_NAMES = %i[
    _require allow_reentry ascend basename binread binwrite descend disable downto each each_child each_entry
    each_filename each_line enable expand_path fetch_values fnmatch fnmatch? freeze glob initialize irb loop map
    mkdir new open opendir read readlines realdirpath realpath require select send shareable_lambda shareable_proc
    store_if_absent sub synchronize sysopen tap then times to_set trace unpack with_jit write
  ].freeze
  private_constant :CORE_BLOCK_NAMES

  # The runtime's way in when a method `name` that never uses its block
  # gets one (lib/zr/runtime/kernel/class.rb, zr_unused_block). Ruby shows
  # it under a true $VERBOSE or the strict_unused_block category;
  # `relaxed` tells that another method of the program with the name uses
  # its block, which only the category ignores.
  def self.unused_block(message, relaxed, name)
    Primitive.attr! :hidden
    strict = self[:strict_unused_block]
    return nil if (relaxed || CORE_BLOCK_NAMES.include?(name)) && !strict
    return nil unless strict || $VERBOSE

    warn(message)
  end

  # The runtime's way in when a program redefines a method of the core
  # (lib/zr/runtime/kernel/class.rb, zr_warn_core_redefined): false where ruby
  # gives no warning, nil for a warning that names no line, the
  # <internal:*> line of the previous definition, or true for a name that
  # is not one of ruby's methods, which the runtime judges by itself.
  def self.redefinition(klass, name)
    Primitive.attr! :hidden
    if klass.singleton_class?
      owner = klass.attached_object
      return true unless owner.is_a?(Module)

      key = "#{owner.name}.#{name}"
    else
      key = "#{klass.name}##{name}"
    end
    REDEFINITIONS.fetch(key, true)
  end

  extend self
end
