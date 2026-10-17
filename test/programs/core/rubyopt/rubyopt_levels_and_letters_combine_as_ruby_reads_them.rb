# RUBYOPT's letters combine in one word (-wU), a later level wins over an
# earlier one, and -U makes UTF-8 the default internal encoding.
p $VERBOSE, $DEBUG, Warning[:deprecated]
p Encoding.default_internal
