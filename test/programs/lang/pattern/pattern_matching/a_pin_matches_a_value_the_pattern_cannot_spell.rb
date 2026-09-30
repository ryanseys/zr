# frozen_string_literal: true

# A pin matches a value the pattern cannot spell, and any object whose
# `===` answers.
expected = 5
case 5
in ^expected then p :pinned
end

case 3
in ^(1 + 2) then p :pinned_expression
end

over_three = ->(v) { v > 3 }
case 5
in ^over_three then p :pinned_proc
end

