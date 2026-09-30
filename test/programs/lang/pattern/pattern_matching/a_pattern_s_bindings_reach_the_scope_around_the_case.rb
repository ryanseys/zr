# frozen_string_literal: true

# The bindings reach the scope around the `case`.
case { name: "zr", version: [0, 1, 0] }
in { name: String => found, version: [major, minor, *] }
  nil
end
p found, major, minor

