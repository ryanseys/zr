# Members that ruby has: RbConfig::DESTDIR and fire_update!, the ISeq
# loaders, and Ractor::Port#initialize_copy, which refuses as ruby's does.
require "rbconfig"
p RbConfig::DESTDIR, RbConfig::CONFIG["DESTDIR"].equal?(RbConfig::DESTDIR), RbConfig.method(:fire_update!).arity
I = RubyVM::InstructionSequence
p I.compile_parsey("1 + 2").eval, (I.load_from_binary_extra_data("x") rescue $!)
p Ractor::Port.private_instance_methods(false).sort, (Ractor::Port.new.dup rescue $!)
mk = { "a" => "1", "b" => "$(a)2" }
conf = { "a" => "1", "b" => "12" }
p RbConfig.fire_update!("a", "9", mk, conf), conf, RbConfig.fire_update!("a", "9", mk, conf)
