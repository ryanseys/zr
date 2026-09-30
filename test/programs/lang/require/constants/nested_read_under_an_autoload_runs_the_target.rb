# An `autoload` names a NAMESPACE far more often than it names the leaf a
# program reads: net/http writes `autoload :OpenSSL, "openssl"` and then reads
# `OpenSSL::SSL::SSLContext`. The read has to run the target when it reaches
# any PREFIX of the path that is an autoload, not only the whole path.
#
# If the target does not run, the read raises `uninitialized constant`. An
# HTTPS request in `Net::HTTP#connect` reads a constant this way.
$LOAD_PATH.unshift(File.expand_path("autoload_nested", __dir__))

puts "before"
autoload :NS, File.expand_path("autoload_nested/ns", __dir__)
puts "after the declaration"

# Nothing has run yet.
p Object.autoload?(:NS)&.end_with?("ns")

# A read three levels down the namespace must run it.
puts "first read"
p NS::Inner::Deep.hi
p NS::LOADED
p Object.autoload?(:NS)
