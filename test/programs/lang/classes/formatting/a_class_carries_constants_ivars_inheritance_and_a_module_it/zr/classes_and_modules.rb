class Animal
  LEGS = 4

  def initialize(name)
    @name = name
    @sounds = 0
  end

  def name
    @name
  end

  def legs
    LEGS
  end

  def speak
    "..."
  end

  def describe
    "#{name} says #{speak}"
  end

  def heard
    @sounds += 1
    @sounds
  end

  def to_s
    "<#{self.class}: #{@name}>"
  end
end

class Dog < Animal
  def speak
    "woof"
  end
end

class Puppy < Dog
  def speak
    "yip"
  end
end

class Stack
  def initialize
    @items = []
  end

  def push(v)
    @items << v
    self
  end

  def each
    @items.each { |i| yield i }
    self
  end

  def size
    @items.size
  end
end

class Counter
  def self.build
    new
  end

  def self.label
    "counter"
  end

  def initialize
    @n = 0
  end

  def bump
    @n += 1
    self
  end

  def value
    @n
  end
end

module Greeting
  WORD = "hi"

  def self.hello
    WORD
  end
end

a = Animal.new("cat")
d = Dog.new("rex")
pup = Puppy.new("bit")

p a.describe
p d.describe
p pup.describe
p a.legs
p d.class
p Puppy.ancestors.first(4)
p Puppy.superclass
p d.is_a?(Animal)
p d.is_a?(Puppy)
puts d
p a.heard
p a.heard
p Animal::LEGS
p Animal.instance_methods(false).sort

[Animal.new("a"), Dog.new("b"), Puppy.new("c")].each { |x| puts x.describe }

s = Stack.new
s.push(1).push(2).push(3)
p s.size
total = 0
s.each { |i| total += i }
p total

c = Counter.build
p c.bump.bump.bump.value
p Counter.label
p Counter.instance_methods(false).sort

p Greeting.hello
p Greeting.class
p Greeting::WORD

def boom(x)
  x.speak
end
p boom(d)

class Account
  attr_accessor :balance
  attr_reader :owner
  attr_writer :note

  def initialize(owner, balance)
    @owner = owner
    @balance = balance
    @note = ""
  end

  def summary = "#{@owner}: #{@balance} #{@note}"

  private

  def secret = :hidden

  protected

  def guarded = :maybe

  public

  def open = :yes
end

# Ruby's visibility barrier is a question about the SITE: a receiverless
# call asks nothing, and an explicit receiver is measured against the
# class of `self` where the call is written.
class Vault < Account
  # A sibling reaches a protected method; `self` here IS an Account.
  def kin?(other) = guarded == other.guarded

  # In a class method `self` is the class, which is no kind of Account,
  # so the same call is refused.
  def self.peek(a) = a.guarded

  # A receiverless call and an explicit `self` both reach a private one.
  def both = [secret, open]
end

class Savings < Account
  attr_reader :rate

  def initialize(owner, balance, rate)
    @owner = owner
    @balance = balance
    @note = "s"
    @rate = rate
  end

  def named = :n
  private :named
end

hi = Vault.new("hi", 9)
lo = Vault.new("lo", 2)
p hi.kin?(lo)
p hi.both

[["protected", -> { hi.guarded }],
 ["private", -> { hi.secret }],
 ["from a class method", -> { Vault.peek(hi) }]].each do |what, go|
  p [what, go.call]
rescue NoMethodError => e
  p [what, e.message]
end

p Account.instance_methods(false).sort
p Account.private_instance_methods(false).sort
p Account.protected_instance_methods(false).sort
p Savings.private_instance_methods(false).sort
p Account.instance_method(:balance).parameters
p Account.instance_method(:balance=).parameters
p Account.instance_method(:balance).arity
p Account.instance_method(:balance=).arity
p Account.instance_method(:balance).source_location.last

acct = Account.new("ada", 10)
p acct.owner, acct.balance, acct.summary
acct.balance = 25
acct.note = "!"
p acct.balance, acct.summary
p acct.instance_variables

sav = Savings.new("bob", 5, 2)
p sav.owner, sav.balance, sav.rate, sav.summary
sav.balance = 7
p sav.balance, sav.instance_variables
p acct.send(:secret), sav.send(:named)

class Boom < StandardError
end

class Louder < Boom
  attr_accessor :code
end

class Bad < ArgumentError
end

p Boom.superclass, Louder.superclass, Bad.superclass
p Boom.ancestors.first(5)
p Boom.new("hi").message
p Boom.new.message
p Louder.new("x").is_a?(StandardError)
p Louder.new("x").is_a?(Boom)
p Bad.new("y").is_a?(ArgumentError)
p Boom.instance_methods(false)

loud = Louder.new("m")
loud.code = 7
p loud.code, loud.message, loud.instance_variables


class Walker
  def initialize(name)
    @name = name
  end

  def step = "..."
  def trail = "#{@name} #{step}"

  def each
    yield 1
    yield 2
  end
end

class Runner < Walker
  def initialize(name, pace)
    super(name)
    @pace = pace
  end

  def step = "#{super}!"
  def trail = "#{super} @#{@pace}"

  def each(&blk) = super(&blk)
end

class Sprinter < Runner
  def step = "#{super}#{super}"

  def each
    super { |v| yield v * 10 }
  end
end

p Walker.new("w").trail
p Runner.new("r", 5).trail
p Sprinter.new("s", 9).trail
p Sprinter.new("s", 9).step

seen = []
Sprinter.new("s", 1).each { |v| seen << v }
p seen

class Quiet < Walker
  def step(loud = "shh") = super()
end
p Quiet.new("q").step

class Boom2 < StandardError
  def initialize(msg = "boom")
    super
  end
end

class Louder2 < Boom2
  def initialize(msg)
    super("#{msg}!")
  end
end

p Boom2.new.message, Boom2.new("x").message, Louder2.new("y").message
p Louder2.new("y").is_a?(StandardError)


class Ledger
  TOTAL = 0
  SECRET = :hidden
  private_constant :SECRET

  attr_reader :rows

  def initialize = @rows = []

  private def stamp(row) = "#{row}!"

  def add(row)
    @rows << stamp(row)
    self
  end

  alias push add

  def size = @rows.size
  alias_method :count, :size
end

led = Ledger.new
led.add("a").push("b")
p led.rows, led.size, led.count
p Ledger::TOTAL
p Ledger.constants.sort
p Ledger.private_instance_methods(false).sort
p Ledger.instance_methods(false).sort

begin
  Ledger::SECRET
rescue NameError => e
  p e.class, e.message
end

def blow_up
  raise Louder, "went wrong"
end
blow_up
