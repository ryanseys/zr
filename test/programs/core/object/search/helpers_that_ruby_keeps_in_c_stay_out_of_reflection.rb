# Helpers that ruby keeps in C are out of reflection's sight: Errno's
# lookups, Ruby::Box's privates, the initialize of three C classes,
# IO::Buffer's own flags, and a second File::Constants in File.
require "monitor"
p Errno.singleton_methods.sort, Ruby::Box.private_instance_methods(false).sort
p Enumerator::Producer.private_instance_methods(false), Thread::Backtrace::Location.private_instance_methods(false)
p Monitor.private_instance_methods(false), IO::Buffer.constants.include?(:SLICE), IO::Buffer.method_defined?(:to_str)
p File.ancestors.take(4), File::NONBLOCK == IO::NONBLOCK
