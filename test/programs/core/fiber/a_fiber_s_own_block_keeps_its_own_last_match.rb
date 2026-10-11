# `$~` and `$_` that a Fiber's or a Thread's own block sets belong to
# that stack, not to the method that made the block (rb_fiber_start
# sets ec->root_lep to the block's lep, so the block's svars go to
# ec->root_svar). test_fiber.rb's test_separate_lastmatch.
def in_a_fiber
  /a/ =~ "a"
  inner = nil
  Fiber.new do
    p $~                      # the fiber starts with no match
    /b/ =~ "b"
    inner = $~
    [1].each { /c/ =~ "c" }   # a block in the fiber's block shares its $~
    p $~[0]
  end.resume
  [inner[0], $~[0]]
end
p in_a_fiber

def in_a_thread
  /a/ =~ "xa"
  Thread.new { /t/ =~ "t"; $~[0] }.value.then { [_1, $~[0]] }
end
p in_a_thread

def two_resumes
  /a/ =~ "a"
  f = Fiber.new do
    /b/ =~ "b"
    Fiber.yield
    $~[0]                     # still the fiber's own match
  end
  f.resume
  /z/ =~ "z"
  [f.resume, $~[0]]
end
p two_resumes

# A proc called after its method returned still reads that method's $~.
def made
  /m/ =~ "m"
  proc { $~[0] }
end
p made.call

# A block that a method gives to a Fiber made elsewhere keeps the
# method's $~ only while it runs on the method's stack.
def handed(&blk) = Fiber.new(&blk).resume
def caller_side
  /q/ =~ "q"
  [handed { $~ }, $~[0]]
end
p caller_side
