# frozen_string_literal: true

# A guard is its own reason: the pattern matched and the condition did
# not.
case [1, 2, 3]
in [Integer => first, *] if first.positive? then p [:guard, first]
end

case [4]
in [only] unless only.zero? then p [:unless, only]
end

p((1 in Integer))
p(([1, 2] in [_, _]))
p(({ a: 1 } in { a: Integer }))
p((:z in Integer))

held = { a: 1, b: 2 }
held => { a: }
p a

