# A compound index assignment (`arr[i] += 1`) is the LAST statement
# of a method or `begin` body, so its value is the value of the
# body. Most code puts a statement after it.

class Bumper
  def bump
    arr = [10]
    arr[0] += 1
  end
end
puts Bumper.new.bump
