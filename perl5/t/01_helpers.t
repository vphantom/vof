use strict;
use warnings;
use Test::More;
use VOF qw(:helpers :constants :constructors);

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
	is(decimal_of_string("-"), undef, "bare minus sign");
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

# ===== detect_format =====

subtest 'detect_format' => sub {
	# Constants
	is(detect_format("\x1F"), VOF_FMT_GZIP, "gzip");
	is(detect_format("\x28"), VOF_FMT_ZSTD, "zstd");

	# JSON: 0x5B, 0x6E, 0x7B
	is(detect_format("["), VOF_FMT_JSON, "json array");
	is(detect_format("n"), VOF_FMT_JSON, "json null");
	is(detect_format("{"), VOF_FMT_JSON, "json object");

	# CBOR: 0x80..0xDB, 0xF6
	is(detect_format("\x80"), VOF_FMT_CBOR, "cbor low boundary");
	is(detect_format("\xDB"), VOF_FMT_CBOR, "cbor high boundary");
	is(detect_format("\xA0"), VOF_FMT_CBOR, "cbor mid-range");
	is(detect_format("\xF6"), VOF_FMT_CBOR, "cbor null");
	is(detect_format("\xDC"), undef, "cbor+1 gap");

	# Binary: 0xE8..0xF3, 0xFA..0xFD
	is(detect_format("\xE8"), VOF_FMT_BINARY, "binary low boundary");
	is(detect_format("\xF3"), VOF_FMT_BINARY, "binary first range high");
	is(detect_format("\xFA"), VOF_FMT_BINARY, "binary second range low");
	is(detect_format("\xFD"), VOF_FMT_BINARY, "binary high boundary");
	is(detect_format("\xF4"), undef, "binary gap between ranges");
	is(detect_format("\xFE"), undef, "binary+1 above");

	# Unrecognized / edge cases
	is(detect_format("\x00"), undef, "null byte");
	is(detect_format("A"), undef, "plain ASCII");
	is(detect_format(undef), undef, "undef input");
	is(detect_format(""), undef, "empty string");

	# Longer buffer — only first byte examined
	is(detect_format("\x1Fgarbage"), VOF_FMT_GZIP, "longer buffer");
};

# ===== is_ref =====

subtest 'is_ref' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("thing",
		keys     => ["id"],
		required => ["name"],
	);

	my $full = vof_record($s, {
		id    => vof_int(1),
		name  => vof_string("Alice"),
		extra => vof_int(42),
	});
	is(is_ref($full), 0, "full record is not a ref");

	my $ref = vof_record($s, {
		id   => vof_int(1),
		name => vof_string("Alice"),
	});
	is(is_ref($ref), 1, "keys + required only is a ref");

	my $keys_only = vof_record($s, {
		id => vof_int(1),
	});
	is(is_ref($keys_only), 1, "keys only is a ref");

	my $empty = vof_record($s, {});
	is(is_ref($empty), 1, "empty record is a ref");

	is(is_ref(vof_int(1)), 0, "non-record returns false");
	is(is_ref(undef), 0, "undef returns false");
};

# ===== make_ref =====

subtest 'make_ref' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("item",
		keys     => ["id"],
		required => ["mtime"],
	);

	my $full = vof_record($s, {
		id    => vof_int(7),
		mtime => vof_int(1000),
		desc  => vof_string("widget"),
		qty   => vof_int(3),
	});

	my $ref = make_ref($full);
	ok(defined $ref, "make_ref returns defined value");
	is(ref $ref, 'VOF::Value', "result is a VOF::Value");
	is($ref->[0], VOF_RECORD, "result is a record");
	is_deeply(
		[sort keys %{$ref->[2]}],
		[qw(id mtime)],
		"only key and required fields remain",
	);
	is($ref->[2]{id}[1], 7, "key value preserved");
	is($ref->[2]{mtime}[1], 1000, "required value preserved");
	is(is_ref($ref), 1, "make_ref result passes is_ref");

	# Already a ref — idempotent
	my $ref2 = make_ref($ref);
	is_deeply(
		[sort keys %{$ref2->[2]}],
		[sort keys %{$ref->[2]}],
		"make_ref on a ref is idempotent",
	);

	# Non-record returns undef
	is(make_ref(vof_string("hello")), undef, "non-record returns undef");
	is(make_ref(undef), undef, "undef returns undef");
};

# ===== pp =====

subtest 'pp smoke' => sub {
	is(pp(vof_null()), 'NULL', 'null');
	is(pp(vof_bool(1)), 'TRUE', 'true');
	is(pp(vof_bool(0)), 'FALSE', 'false');
	is(pp(vof_int(42)), '42', 'int');
	is(pp(vof_int(-5)), '-5', 'negative int');
	is(pp(vof_uint(7)), '7', 'uint');
	ok(length(pp(vof_float(3.14))) > 0, 'float non-empty');
	is(pp(vof_string('hello')), '"hello"', 'string');
	is(pp(vof_string("a\"b\\c")), '"a\\"b\\\\c"', 'string with escapes');
	is(pp(vof_decimal(1235, 1)), '123.5', 'decimal');
	is(pp(vof_ratio(3, 4)), '3/4', 'ratio');
	is(pp(vof_percent(5, 1)), '50%', 'percent');
	is(pp(vof_date(2025, 6, 15)), '2025-06-15', 'date');
	is(pp(vof_datetime(2025, 12, 31, 23, 59)), '2025-12-31T23:59', 'datetime');
	is(pp(vof_timestamp(1750800000)), '1750800000', 'timestamp');
	is(pp(vof_timespan(24, -1, 0)), 'timespan[24,-1,0]', 'timespan');
	is(pp(vof_code('ABC')), 'ABC', 'code');
	is(pp(vof_currency('USD')), 'USD', 'currency');
	is(pp(vof_language('en')), 'en', 'language');
	is(pp(vof_country('CA')), 'CA', 'country');
	is(pp(vof_amount(1250, 2, 'USD')), '12.5USD', 'amount with currency');
	is(pp(vof_amount(1250, 2)), '12.5', 'amount without currency');
	is(pp(vof_quantity(3, 0, 'KGM')), '3KGM', 'quantity with unit');
	is(pp(vof_quantity(3, 0)), '3', 'quantity without unit');
	is(pp(vof_tax(500, 2, 'GST', 'CAD')), '5CADGST', 'tax with currency');
	is(pp(vof_tax(500, 2, 'GST')), '5GST', 'tax without currency');
	is(pp(vof_coords(45.5, -73.5)), '(45.5,-73.5)', 'coords');

	# Enum and variant (need a schema)
	my $ctx = VOF::Context->new('test');
	my $es = $ctx->schema('status', keys => [], required => []);
	is(pp(vof_enum($es, 'Active')), 'Active', 'enum');
	is(pp(vof_variant($es, 'Error', vof_string('oops'))),
		'Error("oops")', 'variant with arg');
	is(pp(vof_variant($es, 'Ok')), 'Ok', 'variant without args');

	# Types that return "?"
	is(pp(vof_list([vof_int(1)])), '?', 'list returns ?');
	is(pp(vof_text({en => 'hi'})), '?', 'text returns ?');
	is(pp(undef), '?', 'undef returns ?');
};

# ===== pp_ref =====

subtest 'pp_ref' => sub {
	my $ctx = VOF::Context->new('test');

	# Schema with key only (no required)
	my $s1 = $ctx->schema('addr', keys => ['id'], required => []);

	my $ref1 = vof_record($s1, { id => vof_int(1) });
	is(pp_ref($ref1), 'test.addr(1)', 'reference with key only');
	is(pp($ref1), 'test.addr(1)', 'pp delegates to pp_ref');

	my $full1 = vof_record($s1, {
		id   => vof_int(1),
		city => vof_string('Montreal'),
	});
	is(pp_ref($full1), 'test.addr(1;...)', 'full record with key only');

	# Schema with keys and required
	my $s2 = $ctx->schema('order',
		keys     => ['id'],
		required => ['mtime'],
	);

	my $ref2 = vof_record($s2, {
		id    => vof_int(42),
		mtime => vof_int(1000),
	});
	ok(length(pp_ref($ref2)) > 0, 'reference with key+req non-empty');
	unlike(pp_ref($ref2), qr/;\.\.\.\)$/, 'reference has no ;...)');

	my $full2 = vof_record($s2, {
		id    => vof_int(42),
		mtime => vof_int(1000),
		total => vof_decimal(1250, 2),
	});
	like(pp_ref($full2), qr/^test\.order\(/, 'full record starts with path');
	like(pp_ref($full2), qr/;\.\.\.\)$/, 'full record ends with ;...)');

	# Missing key renders as NULL
	my $empty = vof_record($s1, {});
	is(pp_ref($empty), 'test.addr(NULL)', 'missing key shows NULL');

	# Non-record inputs
	is(pp_ref(vof_int(1)), '?', 'non-record returns ?');
	is(pp_ref(undef), '?', 'undef returns ?');
};

done_testing;
