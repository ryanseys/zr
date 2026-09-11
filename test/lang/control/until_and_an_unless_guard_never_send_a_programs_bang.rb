# `until` and an `unless` guard test truthiness as a branch does, so a
# class that defines `!` cannot turn them. `x&.!` is a safe call of `!`.
class Always
  def ! = true
end

n = 0
until Always.new
  n += 1
  break
end
p n

k = 0
k += 1 until k >= 3 || Always.new
p k

r = case 1
    in Integer unless Always.new then :guarded
    else :else
    end
p r

p nil&.!
p Always.new&.!
p(!Always.new)

__END__
0
0
:else
nil
true
true
