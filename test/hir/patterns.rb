case [1, 2, 3]
in [1, *rest] then p rest
end
case { name: "a", age: 2 }
in { name: String => n, age: } then p n, age
end
case 5
in Integer | Float => n if n > 1 then p n
end
case { a: 1, b: 2 }
in { a:, **rest } then p a, rest
end
x = [1, [2, 3]]
case x
in [Integer => head, [_, _] => tail] then p head, tail
end
p((1 in Integer))
{ k: 1 } => { k: }
p k
