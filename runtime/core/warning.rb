# frozen_string_literal: true

# Where every warning goes. A program overrides `Warning.warn` to catch
# them, and turns a category on or off with `Warning[]=`.
module Warning
  CATEGORIES = { deprecated: false, experimental: true, performance: false, strict_unused_block: false }
  private_constant :CATEGORIES

  def self.categories = CATEGORIES.keys

  def self.[](category)
    raise ArgumentError, "unknown category: #{category}" unless CATEGORIES.key?(category)

    CATEGORIES[category]
  end

  def self.[]=(category, flag)
    raise ArgumentError, "unknown category: #{category}" unless CATEGORIES.key?(category)

    Primitive.zr_warn_deprecated_set(flag) if category == :deprecated
    CATEGORIES[category] = flag
  end

  def warn(message, category: nil)
    $stderr.write(message)
    nil
  end

  # The runtime's own way in, for a warning it raises with a category.
  def self.deprecated(message)
    Primitive.attr! :hidden
    return nil if $VERBOSE.nil? || !self[:deprecated]

    warn("#{Primitive.zr_warn_position}warning: #{message}\n", category: :deprecated)
  end

  # The same way in for a feature ruby calls experimental. The notice
  # names the line that reached it, as ruby's does.
  def self.experimental(message)
    Primitive.attr! :hidden
    return nil if $VERBOSE.nil? || !self[:experimental]

    warn("#{Primitive.zr_warn_position}warning: #{message}\n", category: :experimental)
  end

  # The runtime's way in when a program writes over one of the core's
  # basic operators (runtime/kernel/class.rb, zr_warn_operator).
  def self.operator_redefined(klass, name)
    Primitive.attr! :hidden
    return nil unless self[:performance]

    warn("#{Primitive.zr_warn_position}warning: Redefining '#{klass}##{name}' disables interpreter and JIT optimizations\n",
         category: :performance)
  end

  extend self
end
