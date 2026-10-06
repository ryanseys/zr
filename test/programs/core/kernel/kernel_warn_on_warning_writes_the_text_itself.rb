# Kernel#warn with Warning as self writes the text itself and does not
# call Warning.warn, as rb_warning_string does.
$stderr = $stdout
def Warning.warn(*args, **kwargs)
  raise "should not be called"
end
Kernel.instance_method(:warn).bind(Warning).call("Kernel#warn spec edge case")
