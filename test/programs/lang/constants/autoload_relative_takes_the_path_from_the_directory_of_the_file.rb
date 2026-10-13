# ruby 4.1's autoload_relative, on Kernel and Module (Feature #15330):
# autoload of a path taken from the directory of the file that calls it,
# made absolute, which autoload? gives. Code of an eval with no file has
# no directory, and raises LoadError.
require_relative "autoload_relative/main"
