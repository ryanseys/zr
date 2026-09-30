# A value that is no number ends a compensated Float sum: CRuby goes on
# from the sum without the compensation it had gathered, for an Array
# and for any Enumerable.
p [0.1, 0.2, 0.3, 1i].sum, [0.1, 0.2, 0.3, 1i].each.sum
p [1e100, 1.0, -1e100, 1i].sum, [1e100, 1.0, -1e100, 1i].each.sum
p [0.1, 0.2, 0.3, 1r, 1i].sum

