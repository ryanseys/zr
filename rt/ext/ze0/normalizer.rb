# The load CRuby's String#unicode_normalize makes on its first call:
# ruby's own normalize.rb, carried unedited in vendor/lib. A program
# that names one of the three methods carries this file ahead of its
# body, and the load itself waits for that first call, as CRuby's does,
# so the two files join $LOADED_FEATURES only then.
String.send(:normalizer=, -> { require "unicode_normalize/normalize" })
