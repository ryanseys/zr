# A module-level singleton method (`module M; def self.X; ... end; end`)
# whose body returns a non-Integer value. Each call site gets that value,
# whether it goes into a local or straight to `puts`. The class form
# (same shape inside `class C`) works the same way.

# 1. Module + def self + String return + local capture.
module M1
  def self.greet
    "hello"
  end
end

s = M1.greet
puts s                              # hello

# 2. Module + def self + String return + inline puts — same root, different consumer.
module M2
  def self.greet
    "world"
  end
end

puts M2.greet                       # world

# 3. Module + def self + Float return — non-int isn't string-specific.
module M3
  def self.pi
    3.14
  end
end

puts M3.pi                          # 3.14

# 4. Class + def self + String return.
class C1
  def self.greet
    "from class"
  end
end

t = C1.greet
puts t                              # from class

# 5. Top-level def returning String.
def top_greet
  "top"
end

u = top_greet
puts u                              # top
