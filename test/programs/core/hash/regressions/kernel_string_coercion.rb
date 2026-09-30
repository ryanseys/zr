# Kernel#String() coercion calls .to_s for each primitive type.
# nil -> "".
puts String(42)
puts String(nil).inspect
puts String(true)
puts String("hi")
puts String(:sym)
puts String(3.14)
