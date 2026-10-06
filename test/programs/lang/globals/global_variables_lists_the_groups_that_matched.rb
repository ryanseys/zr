# global_variables lists `$1`, `$2`... for each group of `$~` that
# matched, and none when there is no match.
before = global_variables
p before.include?(:$1)
/(\w)(\d)?(.)(.)(.)(.)(.)(.)(.)(.)(\d)?(.)/ =~ "globalglobalglobal"
added = global_variables - before
p added.grep(/\A\$\d+\z/)
"x" =~ /y/
p global_variables.include?(:$1)
