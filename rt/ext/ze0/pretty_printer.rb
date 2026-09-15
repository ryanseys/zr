# The load CRuby's prelude makes on the first call to Kernel#pp: ruby's
# own pp.rb, carried unedited in vendor/lib. A program that names pp
# carries this file ahead of its body, and the load waits for that first
# call, so pp.rb joins $LOADED_FEATURES only then.
Kernel.send(:pretty_printer=, -> { require "pp" })
