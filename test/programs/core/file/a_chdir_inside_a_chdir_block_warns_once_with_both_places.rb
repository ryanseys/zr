# A chdir without a block inside a chdir block warns once, and the one
# message gives both places, as dir_chdir0 passes them to rb_warn.
$warnings = []
def Warning.warn(message, category: nil)
  $warnings << message.gsub(__FILE__, "FILE")
end
start = Dir.pwd
Dir.chdir(start) do
  Dir.chdir(start)
end
p $warnings
