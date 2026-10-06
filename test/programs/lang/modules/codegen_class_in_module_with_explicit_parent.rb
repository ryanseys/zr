# A `class Sub < Parent` written inside a single-level `module M`.
# The compiler resolves the parent class, and the class works.

module M
  class Sub < Object
    def hello; puts "hi"; end
  end
end
M::Sub.new.hello
