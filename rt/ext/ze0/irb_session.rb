# The load CRuby's prelude makes on the first `binding.irb`: irb,
# carried unedited in vendor/lib. A program that names `irb` carries
# this file ahead of its body, and the load waits for that first call,
# so irb joins $LOADED_FEATURES only then.
Binding.send(:irb_session=, -> { require "irb" })
