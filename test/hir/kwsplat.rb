h = { a: 1, b: 2 }
p [**h]
p [**{}]
p [**h, **{ c: 3 }]
def take(*args) = args
p take(**h)
p take(*[1], **h)
