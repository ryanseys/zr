# Module class methods (`def self.X`) that write and read `@ivar`
# use an ivar of the module object itself.

module M
  def self.set(v); @v = v; end
  def self.get; @v; end
end
M.set(42)
puts M.get
M.set(100)
puts M.get
