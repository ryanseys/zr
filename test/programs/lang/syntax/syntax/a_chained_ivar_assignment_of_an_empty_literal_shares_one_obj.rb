# A chained assignment `@a = @b = {}` (or `[]`) puts one new object
# in every ivar of the chain, so a write through one ivar shows
# through the others. The ivars held String-keyed Hashes (or String
# Arrays) before.

# Hash: both ivars held a Hash with String keys and values.
class HashOwner
  def initialize
    @a = {}
    @a["seed"] = "value"
    @b = {}
    @b["seed"] = "value"
  end

  def reset
    @a = @b = {}
  end

  # Write through @a, and read through @b. If the ivars do not share
  # one object, @b has length 0.
  def post_reset_share_check
    @a["after"] = "ok"
    puts @b.length            # 1 if shared, 0 if separate objects
    puts @b["after"]          # "ok" if shared
  end
end

ho = HashOwner.new
ho.reset
ho.post_reset_share_check

# Array: both ivars held an Array of Strings.
class ArrayOwner
  def initialize
    @a = []
    @a.push("x")
    @b = []
    @b.push("y")
  end

  def reset
    @a = @b = []
  end

  def post_reset_share_check
    @a.push("z")
    puts @b.length            # 1 if shared
    puts @b[0]                # "z" if shared
  end
end

ao = ArrayOwner.new
ao.reset
ao.post_reset_share_check

# A chain of three ivars.
class ThreeChain
  def initialize
    @a = {}; @a["s"] = "v"
    @b = {}; @b["s"] = "v"
    @c = {}; @c["s"] = "v"
  end

  def reset
    @a = @b = @c = {}
  end

  def show
    puts @a.length
    puts @b.length
    puts @c.length
  end
end

tc = ThreeChain.new
tc.reset
tc.show
