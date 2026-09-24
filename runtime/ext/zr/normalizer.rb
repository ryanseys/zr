# The load that CRuby's String#unicode_normalize makes on its first call:
# ruby's own normalize.rb, included without changes from vendor/lib. A
# program that calls one of the three methods by name includes this file
# before its body. The load itself waits for that first call, as CRuby's
# does, so the two files join $LOADED_FEATURES only then.
String.send(:normalizer=, -> { require "unicode_normalize/normalize" })
