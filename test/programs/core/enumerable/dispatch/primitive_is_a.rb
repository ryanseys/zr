# is_a? / kind_of? / instance_of? on primitive receivers — answer
# decided at compile time based on Ruby's class hierarchy.

# === Integer ===
p 5.is_a?(Integer)
p 5.is_a?(Numeric)
p 5.is_a?(Comparable)
p 5.is_a?(Object)
p 5.is_a?(Float)
p 5.is_a?(String)
p 5.kind_of?(Integer)
p 5.kind_of?(Numeric)
p 5.instance_of?(Integer)
p 5.instance_of?(Numeric)   # false — instance_of? doesn't follow superclass

# === Float ===
p 1.5.is_a?(Float)
p 1.5.is_a?(Numeric)
p 1.5.is_a?(Comparable)
p 1.5.is_a?(Integer)
p 1.5.kind_of?(Numeric)
p 1.5.instance_of?(Float)
p 1.5.instance_of?(Numeric)

# === String ===
p "hi".is_a?(String)
p "hi".is_a?(Comparable)
p "hi".is_a?(Object)
p "hi".is_a?(Integer)
p "hi".kind_of?(String)
p "hi".instance_of?(String)
p "hi".instance_of?(Comparable)

# === Symbol ===
p :hi.is_a?(Symbol)
p :hi.is_a?(Comparable)
p :hi.is_a?(String)
p :hi.kind_of?(Symbol)
p :hi.instance_of?(Symbol)

# === Top-level ancestors (Kernel / BasicObject) ===
# Every value is in the Object hierarchy, so is_a? returns true for
# Kernel and BasicObject as well as Object. instance_of? still
# returns false for these because they're ancestors, not the exact
# class of the receiver.
p 5.is_a?(Kernel)
p 5.is_a?(BasicObject)
p 1.5.is_a?(Kernel)
p 1.5.is_a?(BasicObject)
p "hi".is_a?(Kernel)
p "hi".is_a?(BasicObject)
p :hi.is_a?(Kernel)
p :hi.is_a?(BasicObject)
p 5.instance_of?(Kernel)
p 5.instance_of?(BasicObject)
