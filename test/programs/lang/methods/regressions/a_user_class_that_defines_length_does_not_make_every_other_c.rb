# Defining `def length` on a class does not change the Integer-array
# params of methods on unrelated classes. A param whose only called
# method is `.length` can still be an Integer array, because every
# built-in container also has `.length`. The call sites decide the
# param's type.

class Mat
  attr_accessor :flat, :nrows, :ncols
  def initialize(nrows, ncols)
    @nrows = nrows
    @ncols = ncols
    @flat  = Array.new(nrows * ncols, 0.0)
  end
end

class Net
  def backward(input_ids, logits)
    n_pred = input_ids.length - 1
    if n_pred <= 0
      return 0.0
    end
    self.cross_entropy_grad(logits, input_ids)
  end

  def cross_entropy_grad(logits, token_ids)
    n     = token_ids.length - 1
    total = 0.0
    i = 0
    while i < n
      target = token_ids[i + 1]
      total += logits.flat[target]
      i += 1
    end
    total
  end
end

def make_ids(s)
  parts = s.split(" ")
  ids   = [parts[0].to_i]
  k = 1
  while k < parts.length
    ids.push(parts[k].to_i)
    k += 1
  end
  ids
end

# The class with `def length` is the trigger. Net#backward and
# Net#cross_entropy_grad must still take Integer-array
# `input_ids` / `token_ids` params.
class Bag
  attr_accessor :data
  def initialize(data); @data = data; end
  def length;           0;             end
end

prompt = make_ids("0 1 2")
puts Net.new.backward(prompt, Mat.new(3, 4))
