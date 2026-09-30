# frozen_string_literal: true

# Every refusal names the same reason the runtime's own raise does.
def refused
  yield
rescue NoMatchingPatternKeyError => e
  [e.class, e.message, e.key, e.matchee]
rescue NoMatchingPatternError => e
  [e.class, e.message]
rescue TypeError, ArgumentError => e
  [e.class, e.message]
end

p refused { 5 => String }
p refused { { a: 1 } => { b: } }

p refused {
  case 9
  in String then 1
  in Float then 2
  end
}

p refused {
  case 9
  in String then 1
  end
}

p refused {
  case [1, 2]
  in [1] then :no
  end
}

p refused {
  case [1, 2, 3]
  in [*, 9, *] then :no
  end
}

p refused {
  case { a: 1, b: 2 }
  in { a:, **nil } then :no
  end
}

p refused {
  case({ a: 1 })
  in {} then :no
  end
}

p refused {
  case 1
  in Integer if false then :no
  end
}

class NotAnArray
  def deconstruct = :nope
end

class NotAHash
  def deconstruct_keys(_keys) = :nope
end

class Angry
  def ===(_other) = raise(ArgumentError, "from ===")
end

p refused {
  case NotAnArray.new
  in [x] then x
  end
}

p refused {
  case NotAHash.new
  in { a: } then a
  end
}

p refused {
  case 1
  in ^(Angry.new) then :no
  end
}
