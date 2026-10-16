p Integer::GMP_VERSION
p Integer::GMP_VERSION.frozen?, Integer.const_defined?(:GMP_VERSION)
p Integer.constants.include?(:GMP_VERSION)
p Integer::GMP_VERSION.match?(/\AGMP \d+\.\d+\.\d+\z/)
