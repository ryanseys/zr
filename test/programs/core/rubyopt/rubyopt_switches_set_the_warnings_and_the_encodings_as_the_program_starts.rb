# ruby reads RUBYOPT as a program starts: here -w and the -W categories
# set the warnings, -E the default encodings, and --backtrace-limit how
# much of an uncaught error's backtrace shows.
p $VERBOSE, $DEBUG
p Warning[:deprecated], Warning[:experimental], Warning[:performance]
p Encoding.default_external, Encoding.default_internal, $stdout.external_encoding
p ENV["RUBYOPT"]
def a = b
def b = c
def c = raise("deep")
a
