# The separators a program sets reach its own code, not the compiler
# that evals its strings.
$, = "-"
$; = ","
$/ = "x"
$\ = "!"
p eval("[1, 2].join"), eval("'a,b c'.split"), eval("[1, 2].to_s")
$, = $; = $\ = nil
$/ = "\n"
require "json"
p JSON.generate({ "a" => [1, 2] })
