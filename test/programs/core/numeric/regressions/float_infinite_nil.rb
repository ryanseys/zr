# Float#infinite?: nil for a finite value, -1 / +1 for -Inf / +Inf.
p 0.0.infinite?
p 3.14.infinite?
p (1.0 / 0.0).infinite?
p (-1.0 / 0.0).infinite?
puts((1.0 / 0.0).infinite? ? "inf" : "finite")
puts(2.5.infinite? ? "inf" : "finite")
