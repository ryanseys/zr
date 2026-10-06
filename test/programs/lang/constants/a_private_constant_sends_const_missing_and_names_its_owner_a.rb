class PCA; X = 1; private_constant :X; end
class PCB < PCA; end
begin; PCB::X; rescue NameError => e; p [e.message, e.name, e.receiver]; end
class PCC < PCA; def self.const_missing(n) = [:missing, n, self]; end
p PCC::X
module PM; Y = 2; private_constant :Y; def self.const_missing(n) = [:mm, n]; end
p PM::Y
module PC2; module Inner; end; private_constant :Inner; end
begin; module PC2::Inner; end; rescue NameError => e; p [e.message, e.receiver]; end
module PC2; module Inner; end; end
p :reopen_inside_ok
class PC3; class Inner; end; private_constant :Inner; end
begin; class PC3::Inner; end; rescue NameError => e; p [e.message, e.receiver]; end
Foo = 1; Object.private_constant :Foo
begin; Object::Foo; rescue NameError => e; p [e.message, e.receiver]; end
class Bar; end; Object.private_constant :Bar
begin; class ::Bar; end; rescue => e; p [e.class, e.message]; end
class Bar; def x = 1; end
p Bar.new.x
