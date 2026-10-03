x = { alpha: "a" * 30, beta: "b" * 30, gamma: [1, 2, 3] * 5 }
name = ARGV.empty? ? :pp : :p
send(name, x)
send("pp", [x[:alpha], x[:beta], x[:gamma]])
m = method(name)
m.call({ short: 1 })
