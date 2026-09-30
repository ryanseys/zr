# %f of an Integer or a Rational writes its exact digits, the magnitude
# rounded half up, as CRuby's sprintf does; %e goes through a Float.
def t = yield rescue [$!.class, $!.message]

p t { format("%.20f", 1/3r) }, t { format("%f", 1/3r) }, t { format("%.3f", 2/3r) }
p t { format("%.0f", 5/2r) }, t { format("%.0f", 7/2r) }, t { format("%.0f", -5/2r) }, t { format("%.1f", -1/20r) }
p t { format("%10.3f|", 1/3r) }, t { format("%-10.3f|", 1/3r) }, t { format("%+.2f", 1/3r) }, t { format("% .2f", 1/3r) }, t { format("%010.3f", -1/3r) }
p t { format("%.2e", 1/3r) }, t { format("%f", 10**30) }, t { format("%.3f", 10**30 + 1/3r) }, t { format("%.2f", 0r) }, t { format("%#.0f", 1/3r) }
p t { format("%.0f", -1/3r) }, t { format("%f", -3) }, t { format("%+08.2f", 7) }, t { format("%-8.1f|", -7) }

