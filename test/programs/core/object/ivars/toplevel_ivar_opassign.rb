# A top-level `@ivar ||=` / `@ivar &&=` stores its value in the ivar of
# `main`.
@y ||= 5
p @y                 # 5
@y ||= 99
p @y                 # 5  (already set, ||= is a no-op)

@s ||= "hi"
p @s                 # "hi"

@a = 3
@a &&= 10
p @a                 # 10
@b &&= 10
p @b                 # nil (unset stays nil under &&=)
