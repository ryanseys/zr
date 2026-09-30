# Defining an instance `empty?` must not drop the builtin String/Array `empty?`
# from a call that can reach either. A String (or Array) receiver runs the
# builtin `empty?`, and a user object runs its own.
class Flasher
  def empty?
    false
  end
end

def pick(c)
  c ? "" : "x"
end
def pickarr(c)
  c ? [] : [1]
end

puts pick(true).empty?     # true
puts pick(false).empty?    # false
puts pickarr(true).empty?  # true
puts pickarr(false).empty? # false
puts Flasher.new.empty?    # false  (user method still dispatches)
