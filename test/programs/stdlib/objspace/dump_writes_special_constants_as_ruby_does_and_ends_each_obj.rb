require "objspace"
# A special constant is its JSON value, a static Symbol its name, and a
# flonum "%#g"; any other object is a line of its own.
p ObjectSpace.dump(nil), ObjectSpace.dump(7), ObjectSpace.dump(:sym), ObjectSpace.dump(1.5)
p ObjectSpace.dump("x").end_with?("}\n"), ObjectSpace.dump(1e300)[/"frozen":true, "value":"[^"]*"/]
p ObjectSpace.dump(Object.new)[/"address":"(0x\h+)"/, 1].match?(/\A0x[1-9a-f]/)
