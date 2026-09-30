# A value that holds a builtin array must still append on push/<</append, even
# when a user class defines push/<<. The user class's own push still runs for
# its object receivers.
class Stack
  def push(x)
    x
  end
end

def pick(flag)
  flag ? [1, 2] : ["a"]   # mixed element kinds -> poly array (poly receiver)
end

arr = pick(true)
arr.push(99)
arr << 100
arr.append(101)
puts arr.length
puts arr.inspect

puts Stack.new.push(7)    # the user push still works on its own object
