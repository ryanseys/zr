# A bare `*` or `**` stands for the anonymous rest parameters wherever
# a splat can: in an array literal and as an index.
def m(*) = [*]
p m(1, 2), m

def n(*) = (h = {k: 1}; h[*] += 1; h)
p n(:k)

def o(**) = [**]
p o, o(a: 1)

def mixed(*, **) = [0, *, **]
p mixed(1, b: 2), mixed

__END__
[1, 2]
[]
{k: 2}
[]
[{a: 1}]
[0, 1, {b: 2}]
[0]
