# rb_str_upcase_bang and its kin read their options first, then refuse a
# frozen receiver, then map. A bang form answers nil when no byte
# changed, with no call of a String#== that the program writes.
def show
  p yield
rescue ArgumentError, FrozenError => e
  p [e.class, e.message]
end

frozen = "Abc".freeze
show { frozen.upcase!(:bogus) }
show { frozen.downcase!(:ascii, :turkic) }
show { frozen.capitalize!(:turkic, :lithuanian, :ascii) }
show { frozen.swapcase!(:fold) }
show { frozen.upcase! }
show { frozen.downcase!(:fold) }
show { "\xFF".dup.force_encoding("UTF-8").freeze.upcase! }
show { "\xFF".dup.force_encoding("UTF-8").upcase! }
show { "Abc".upcase(1, 2, 3) }
show { "Abc".downcase(:turkic, :lithuanian) }
show { "Abc".downcase(:lithuanian, :turkic) }
show { "Abc".downcase(:turkic, :turkic) }

class String
  def ==(other)
    puts "== called"
    super
  end
end

%i[upcase! downcase! capitalize! swapcase!].each do |name|
  same = +"ABC"
  p [name, same.send(name), (+"Ab").send(name)]
end
p (+"ABC").upcase!(:ascii), (+"iI").downcase!(:turkic), (+"ǅ").swapcase!
p (+"abc").delete!("x"), (+"abc").delete!("b"), (+"a").squeeze!, (+"aa").squeeze!
p (+"x").strip!, (+" x ").strip!, (+"x").lstrip!, (+"x ").rstrip!
p (+"x").chomp!, (+"x\n").chomp!, (+"").chomp!, (+"").chop!, (+"xy").chop!
show { "".freeze.chomp! }
show { "x".freeze.delete!("y") }
