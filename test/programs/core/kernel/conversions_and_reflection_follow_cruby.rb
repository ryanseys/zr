# Kernel: Array calls a private to_a, Hash checks what to_hash gives,
# abort converts its message, sleep takes an object with divmod, srand
# converts with to_int, open converts a path, clone passes freeze: on,
# respond_to? asks respond_to_missing? about a private method, raise
# with cause: nil keeps a cause, public_method asks respond_to_missing?
# with false, and Complex checks a String and a part that is not real.
def show
  p yield
rescue Exception => e
  p [e.class, e.message]
end

class PrivateToA
  private def to_a = [3, 4]
end
show { Array(PrivateToA.new) }
bad_hash = Object.new
def bad_hash.to_hash = "string"
show { Hash(bad_hash) }
message = Object.new
def message.to_str = "message"
$stderr = $stdout
show { abort(message) }
$stderr = STDERR
interval = Object.new
# No time at all: a sleep that crosses a second of the wall clock answers 1.
def interval.divmod(_) = [0, 0]
show { sleep(interval) }
seed = Object.new
def seed.to_int = 34
srand(seed)
p srand == 34
show { open(7) }
show { open(nil) }
show { open(__FILE__, nil, nil) { |f| f.gets } }

class CloneFreeze
  attr_reader :kw

  def initialize_clone(orig, **kw)
    super
    @kw = kw
  end
end
p CloneFreeze.new.clone(freeze: true).kw, CloneFreeze.new.clone.kw
class OneArgClone
  def initialize_clone(orig) = super
end
show { OneArgClone.new.clone(freeze: false) }

class Asks
  def respond_to_missing?(name, include_all)
    puts "asked #{name} #{include_all}"
    false
  end

  private def hidden = 1
  def handled_privately = 1
end
p Asks.new.respond_to?(:hidden)

class ViaMissing
  def respond_to_missing?(name, include_all) = include_all
  def method_missing(name, *) = name
end
show { ViaMissing.new.public_method(:handled_privately) }

begin
  begin
    begin
      raise "Error 1"
    rescue => e1
      raise "Error 2"
    end
  rescue => e2
    raise e2, cause: nil
  end
rescue => e
  p e.cause.message
end

show { Complex("1\0") }
p Complex("1\0", exception: false)
show { Complex("1".encode("UTF-16LE")) }
show { Complex(Object.new, 1, exception: false) }
