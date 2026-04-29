use strict;
use warnings;
use Test::More;
use VOF qw(:helpers);

# ===== decimal_of_string =====

subtest 'decimal_of_string basics' => sub {
	is_deeply(decimal_of_string("12.50"), [125, 1], "12.50 trailing zero stripped");
	is_deeply(decimal_of_string("0"), [0, 0], "zero");
	is_deeply(decimal_of_string("100"), [100, 0], "integer");
	is_deeply(decimal_of_string("-5.25"), [-525, 2], "negative");
	is_deeply(decimal_of_string("0.5"), [5, 1], "leading zero");
	is_deeply(decimal_of_string("0.001"), [1, 3], "small decimal");
	is_deeply(decimal_of_string("5.00"), [5, 0], "all trailing zeros stripped");
	is_deeply(decimal_of_string("1.200"), [12, 1], "partial trailing zeros stripped");
	is_deeply(decimal_of_string("-0.5"), [-5, 1], "negative less than one");
	is_deeply(decimal_of_string("2.150"), [215, 2], "spec example 2.150");
};

subtest 'decimal_of_string lenient' => sub {
	is_deeply(decimal_of_string("1,234.56"), [123456, 2], "comma stripped");
	is_deeply(decimal_of_string("50%"), [50, 0], "percent sign stripped");
	is_deeply(decimal_of_string(" 42 "), [42, 0], "whitespace stripped");
};

subtest 'decimal_of_string with shift' => sub {
	is_deeply(decimal_of_string("50", 2), [5, 1], "50 / 100 = 0.5");
	is_deeply(decimal_of_string("100", 2), [1, 0], "100 / 100 = 1");
	is_deeply(decimal_of_string("12.5", 2), [125, 3], "12.5 / 100 = 0.125");
};

subtest 'decimal_of_string invalid' => sub {
	is(decimal_of_string(undef), undef, "undef");
	is(decimal_of_string(""), undef, "empty string");
	is(decimal_of_string("abc"), undef, "non-numeric");
	is(decimal_of_string("."), undef, "bare dot");
};

# ===== decimal_to_string =====

subtest 'decimal_to_string' => sub {
	is(decimal_to_string(125, 1), "12.5", "12.5");
	is(decimal_to_string(5, 0), "5", "integer");
	is(decimal_to_string(0, 0), "0", "zero");
	is(decimal_to_string(-525, 2), "-5.25", "negative");
	is(decimal_to_string(-5, 1), "-0.5", "negative < 1");
	is(decimal_to_string(1, 3), "0.001", "leading fraction zeros");
	is(decimal_to_string(100, 2), "1", "fraction zero → integer");
};

subtest 'decimal_to_string croaks' => sub {
	eval { decimal_to_string(1, -1) };
	like($@, qr/places must be 0\.\.9/, "negative places");
	eval { decimal_to_string(1, 10) };
	like($@, qr/places must be 0\.\.9/, "places > 9");
};

# ===== decimal_optimize =====

subtest 'decimal_optimize' => sub {
	is_deeply([decimal_optimize(1250, 3)], [125, 2], "strip one zero");
	is_deeply([decimal_optimize(100, 2)], [1, 0], "strip all");
	is_deeply([decimal_optimize(123, 2)], [123, 2], "nothing to strip");
	is_deeply([decimal_optimize(0, 0)], [0, 0], "zero");
	is_deeply([decimal_optimize(-50, 2)], [-5, 1], "negative");
};

# ===== ratio helpers =====

subtest 'ratio_of_string' => sub {
	is_deeply(ratio_of_string("3/4"), [3, 4], "positive");
	is_deeply(ratio_of_string("-1/3"), [-1, 3], "negative numerator");
	is_deeply(ratio_of_string("0/1"), [0, 1], "zero");
	is(ratio_of_string(undef), undef, "undef");
	is(ratio_of_string("3/0"), undef, "zero denominator");
	is(ratio_of_string("abc"), undef, "non-numeric");
	is(ratio_of_string("3"), undef, "missing slash");
};

subtest 'ratio_to_string' => sub {
	is(ratio_to_string(3, 4), "3/4", "positive");
	is(ratio_to_string(-1, 3), "-1/3", "negative");
	is(ratio_to_string(0, 1), "0/1", "zero");
};

# ===== date helpers =====

subtest 'date_of_human' => sub {
	is_deeply(date_of_human(20251231), [2025, 12, 31], "valid end-of-year");
	is_deeply(date_of_human(20250101), [2025, 1, 1], "January first");
	is_deeply(date_of_human(10000101), [1000, 1, 1], "year 1000");
	is(date_of_human(undef), undef, "undef");
	is(date_of_human(20251301), undef, "month 13");
	is(date_of_human(20251200), undef, "day 0");
	is(date_of_human(20251232), undef, "day 32");
	is(date_of_human(9991231), undef, "year < 1000");
};

subtest 'date_to_human' => sub {
	is(date_to_human(2025, 12, 31), 20251231, "end-of-year");
	is(date_to_human(2025, 1, 1), 20250101, "January first");
};

# ===== datetime helpers =====

subtest 'datetime_of_human' => sub {
	is_deeply(datetime_of_human(202512312359), [2025, 12, 31, 23, 59], "end-of-year");
	is_deeply(datetime_of_human(202501010000), [2025, 1, 1, 0, 0], "midnight");
	is(datetime_of_human(undef), undef, "undef");
	is(datetime_of_human(202513010000), undef, "month 13");
	is(datetime_of_human(202512312400), undef, "hour 24");
	is(datetime_of_human(202512312360), undef, "minute 60");
};

subtest 'datetime_to_human' => sub {
	is(datetime_to_human(2025, 12, 31, 23, 59), 202512312359, "end-of-year");
	is(datetime_to_human(2025, 1, 1, 0, 0), 202501010000, "midnight");
};

done_testing;
