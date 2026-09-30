# The same shape on an instance method. The method early-returns
# the param when `value.is_a?(Hash)` is false, and else falls
# through to a String. The early `return value` gives the Integer
# as it is.

class Host
  def stringify_keys(value)
    return value unless value.is_a?(Hash)
    "stringified"
  end
end

# The early-return path returns the int parameter as-is.
puts Host.new.stringify_keys(42)

# The fall-through path returns the pointer-shaped value.
puts Host.new.stringify_keys({"a" => 1})
