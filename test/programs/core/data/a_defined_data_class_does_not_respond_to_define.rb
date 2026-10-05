# setup_data undefines `define` on each class that Data.define makes.
klass = Data.define(:a)
p klass.respond_to?(:define)
p Data.respond_to?(:define)
p((klass.define(:b) rescue $!.class))
p Class.new(klass).respond_to?(:define)
