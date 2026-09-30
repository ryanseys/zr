# Immediate-receiver edges: <=> between equal bools/nils is 0, a bool has no
# #=~ so !~ raises, TrueClass/FalseClass/NilClass have no allocator, and
# clone(freeze: false) cannot unfreeze an immediate.
p(true <=> true)
p(false <=> false)
p(true <=> false)
p(nil <=> nil)
r = (true !~ /x/ rescue $!.class); p r
r = (TrueClass.new rescue $!.message); p r
r = (FalseClass.new rescue $!.class); p r
r = (NilClass.new rescue $!.message); p r
r = (true.clone(freeze: false) rescue $!.message); p r
r = (5.clone(freeze: false) rescue $!.message); p r
r = (:a.clone(freeze: false) rescue $!.message); p r
p("s".clone(freeze: false).frozen?)
