# A constant name may start with a non-ASCII uppercase or titlecase
# letter, and an uninitialized constant names its scope by the scope's
# own name, or by its inspect when the name is nil.
p "ἍBB".match?(/\A[\p{Lu}\p{Lt}]/), "ǅx".match?(/\A[\p{Lu}\p{Lt}]/), "éx".match?(/\A[\p{Lu}\p{Lt}]/), "Éx".match?(/\A\p{Upper}/)
mod = Module.new
mod.const_set("ἍBB", 1)
p mod.constants, eval("mod::ἍBB")
begin; mod.const_set("éB", 1); rescue NameError => e; p e.message; end
m2 = Module.new { def self.name = "ModuleName"; def self.inspect = "<unusable info>" }
begin; m2::DOES_NOT_EXIST; rescue NameError => e; p e.message; end
m3 = Module.new { def self.name = nil; def self.inspect = "<unusable info>" }
begin; m3::DOES_NOT_EXIST; rescue NameError => e; p e.message; end
begin; m3.const_get(:NOPE); rescue NameError => e; p e.message; end
p Module.new.const_set("ǅx", 2)
begin; Module.new.const_set("ⅰx", 1); rescue NameError => e; p e.message; end
