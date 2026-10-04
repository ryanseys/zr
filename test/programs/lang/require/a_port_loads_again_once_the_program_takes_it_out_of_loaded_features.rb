# A port of a C extension that the program loads a second time, after it
# took the file out of $LOADED_FEATURES, loads cleanly, as ruby calls the
# extension's Init again.
name = ["io/", "console"].join
p require(name)
$LOADED_FEATURES.delete_if { |f| f.include?("io/console") }
verbose, $VERBOSE = $VERBOSE, nil
p require(name)
$VERBOSE = verbose
p IO::ConsoleMode.private_method_defined?(:initialize)
