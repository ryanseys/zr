# A nested write g[r][c] = v where r/c come from destructuring must land on
# the inner array, for String and Float arrays too.
grid = [["a", "b"], ["c", "d"]]
cells = [[0, 1]]
r, c = cells.first
grid[r][c] = "X"
p grid
fg = [[1.0, 2.0]]
fr, fc = [[0, 1]].first
fg[fr][fc] = 9.0
p fg
