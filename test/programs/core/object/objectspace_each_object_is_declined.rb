# ObjectSpace.each_object is DECLINED: zr has no heap enumeration (objects
# are native values with no global registry), and the row raises a
# NotImplementedError saying so. The divergence is stepped around here -- the
# row exists and reflects on both sides; only CALLING it differs, and this
# test documents that without doing so.
puts ObjectSpace.respond_to?(:each_object).inspect
puts defined?(ObjectSpace.each_object).inspect
