# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# OptionParser's own graph, reached through the required file. See optparse_subset.rb.gccheck.
# At exit: cycle leak: 28 objects (Hash x6, OptionParser::OptionMap x4, Proc x4, cell x4, Array x3, OptionParser::List x2, OptionParser::Switch::OptionalArgument x2, OptionParser x1, OptionParser::Switch::NoArgument x1, OptionParser::Switch::RequiredArgument x1)
# A `require` on the very first line (byte 0) loads its file, also when
# another `require` follows it. Both requires must load.
require "optparse"
require "set"
o = OptionParser.new
puts o.class
