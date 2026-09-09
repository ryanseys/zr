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

    CATEGORIES[category] = flag
  end

  def warn(message, category: nil)
    $stderr.write(message)
    nil
  end

  # The runtime's own way in, for a warning it raises with a category.
  def self.deprecated(message)
    Primitive.attr! :hidden
    return nil unless self[:deprecated]

    warn("#{Primitive.zr_warn_position}warning: #{message}\n", category: :deprecated)
  end

  extend self
end
