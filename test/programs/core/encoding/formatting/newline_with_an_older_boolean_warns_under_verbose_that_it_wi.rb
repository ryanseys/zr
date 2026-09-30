$VERBOSE = true
# Under $VERBOSE, newline: with an older boolean warns that it wins.
p "a\n".encode("UTF-8", "UTF-8", newline: :crlf, cr_newline: true)
p Encoding::Converter.new("UTF-8", "EUC-JP", newline: :cr, crlf_newline: true).convpath.drop(1)
