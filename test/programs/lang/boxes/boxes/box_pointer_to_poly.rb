# A method returns a Hash from one branch and a String from the other.
# The example only checks that the program compiles and runs.

def get(flag)
  if flag > 0
    return {a: 1, b: 2, c: 3}
  end
  "hello"
end

x = get(0)
y = get(1)
puts "ok"
