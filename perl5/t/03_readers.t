use strict;
use warnings;
use Test::More;
use Socket qw(AF_INET AF_INET6 inet_pton);
use VOF qw(:readers :constructors :constants :helpers);

# Shorthand for building raw values
sub raw_int  { VOF::Value->new(VOF_RAW_TINT, $_[0]) }
sub raw_str  { VOF::Value->new(VOF_RAW_TSTR, $_[0]) }
sub raw_list { VOF::Value->new(VOF_RAW_TLIST, $_[0]) }

# ===== as_bool =====

subtest 'as_bool' => sub {
	is(as_bool(vof_null()), 0, "null → false");
	is(as_bool(vof_bool(1)), 1, "true → 1");
	is(as_bool(vof_bool(0)), 0, "false → 0");
	is(as_bool(vof_int(42)), 1, "nonzero int → true");
	is(as_bool(vof_int(0)), 0, "zero int → false");
	is(as_bool(vof_float(0.0)), 0, "zero float → false");
	is(as_bool(vof_float(1.5)), 1, "nonzero float → true");
	is(as_bool(vof_decimal("5.0")), 1, "nonzero decimal → true");
	is(as_bool(vof_decimal("0")), 0, "zero decimal → false");
	is(as_bool(vof_amount(0, 0, "USD")), 0, "zero amount → false");
	is(as_bool(vof_amount(1, 0, "USD")), 1, "nonzero amount → true");
	is(as_bool(vof_text({ en => "hi" })), 1, "non-empty text → true");
	is(as_bool(vof_text({})), 0, "empty text → false");
	is(as_bool(vof_list([])), 0, "empty list → false");
	is(as_bool(vof_list([vof_int(1)])), 1, "non-empty list → true");
	is(as_bool(vof_uint(1)), 1, "nonzero uint → true");
	is(as_bool(vof_uint(0)), 0, "zero uint → false");
	is(as_bool(vof_ratio(3, 4)), 1, "nonzero ratio → true");
	is(as_bool(vof_ratio(0, 1)), 0, "zero ratio → false");
	is(as_bool(vof_percent("50%")), 1, "nonzero percent → true");
	is(as_bool(vof_percent(0, 0)), 0, "zero percent → false");
	is(as_bool(vof_quantity(5, 0, "KGM")), 1, "nonzero quantity → true");
	is(as_bool(vof_quantity(0, 0)), 0, "zero quantity → false");
	is(as_bool(vof_tax(125, 1, "GST")), 1, "nonzero tax → true");
	is(as_bool(vof_tax(0, 0, "GST")), 0, "zero tax → false");
	is(as_bool(vof_strmap({ a => vof_int(1) })), 1, "non-empty strmap → true");
	is(as_bool(vof_strmap({})), 0, "empty strmap → false");
	is(as_bool(vof_uintmap({ 0 => vof_int(1) })), 1, "non-empty uintmap → true");
	is(as_bool(vof_uintmap({})), 0, "empty uintmap → false");
	is(as_bool(raw_int(5)), 1, "raw int nonzero");
	is(as_bool(raw_int(0)), 0, "raw int zero");
	is(as_bool(undef), undef, "undef → undef");
	is(as_bool(vof_string("hi")), undef, "string → undef (no bool coercion)");
};

# ===== as_int =====

subtest 'as_int' => sub {
	is(as_int(raw_int(42)), 42, "raw int");
	is(as_int(raw_int(-7)), -7, "raw negative int");
	is(as_int(vof_int(99)), 99, "typed int");
	is(as_int(vof_uint(10)), 10, "uint → int");
	is(as_int(raw_str("123")), 123, "raw string of digits");
	is(as_int(raw_str("-5")), -5, "raw string negative");
	is(as_int(raw_str("abc")), undef, "raw non-numeric string");
	is(as_int(vof_string("77")), 77, "typed string of digits");
	is(as_int(vof_string("abc")), undef, "typed non-numeric string");
	is(as_int(vof_float(1.5)), undef, "float → undef");
	is(as_int(undef), undef, "undef");
};

# ===== as_uint =====

subtest 'as_uint' => sub {
	is(as_uint(raw_int(42)), 42, "raw int");
	is(as_uint(vof_uint(10)), 10, "typed uint");
	is(as_uint(vof_int(5)), 5, "positive int → uint");
	is(as_uint(vof_int(-1)), undef, "negative int → undef");
	is(as_uint(raw_str("99")), 99, "raw string of digits");
	is(as_uint(raw_str("abc")), undef, "raw non-numeric string");
	is(as_uint(vof_float(1.0)), undef, "float → undef");
};

# ===== as_float =====

subtest 'as_float' => sub {
	ok(abs(as_float(vof_float(3.14)) - 3.14) < 1e-10, "typed float");
	is(as_float(raw_int(42)), 42.0, "raw int → float");
	ok(abs(as_float(raw_str("2.5")) - 2.5) < 1e-10, "raw string → float");
	ok(abs(as_float(raw_str("1e3")) - 1000) < 1e-10, "scientific notation");
	is(as_float(vof_int(7)), 7.0, "typed int → float");
	is(as_float(vof_uint(3)), 3.0, "typed uint → float");
	ok(abs(as_float(vof_string("2.5")) - 2.5) < 1e-10, "typed string → float");
	is(as_float(vof_string("abc")), undef, "typed non-numeric string");
	is(as_float(raw_str("abc")), undef, "non-numeric string");
	is(as_float(vof_null()), undef, "null → undef");
	is(as_float(vof_bool(1)), undef, "bool → undef");
};

# ===== as_string =====

subtest 'as_string' => sub {
	is(as_string(vof_string("hi")), "hi", "typed string");
	is(as_string(raw_str("hello")), "hello", "raw string");
	is(as_string(vof_int(42)), "42", "int stringified");
	is(as_string(vof_code("ABC")), "ABC", "code → string");
	is(as_string(vof_currency("USD")), "USD", "currency → string");
	is(as_string(vof_uint(10)), "10", "uint stringified");
	is(as_string(raw_int(77)), "77", "raw int stringified");
	is(as_string(vof_float(1.5)), undef, "float → undef");
};

# ===== as_data =====

subtest 'as_data' => sub {
	is(as_data(vof_data("\x00\xFF")), "\x00\xFF", "typed data passthrough");
	# base64url round-trip: "AAAA" decodes to "\x00\x00\x00"
	is(as_data(raw_str("AAAA")), "\x00\x00\x00", "base64url decode from raw_str");
	is(as_data(vof_string("AAAA")), "\x00\x00\x00", "base64url decode from typed string");
	is(as_data(raw_int(42)), undef, "int → undef");
};

# ===== Code readers (aliases of as_string) =====

subtest 'code readers' => sub {
	my $v = vof_language("en");
	is(as_language($v), "en", "as_language");
	is(as_country(vof_country("CA")), "CA", "as_country");
	is(as_subdivision(vof_subdivision("QC")), "QC", "as_subdivision");
	is(as_currency(vof_currency("USD")), "USD", "as_currency");
	is(as_tax_code(vof_tax_code("CA_GST")), "CA_GST", "as_tax_code");
	is(as_unit(vof_unit("KGM")), "KGM", "as_unit");
	is(as_code(vof_code("X1")), "X1", "as_code");
};

# ===== as_decimal =====

subtest 'as_decimal' => sub {
	is_deeply(as_decimal(vof_decimal("12.50")), [125, 1], "typed decimal");
	is_deeply(as_decimal(raw_str("3.14")), [314, 2], "raw string");
	is_deeply(as_decimal(vof_percent(5, 1)), [5, 1], "percent → decimal");
	is_deeply(as_decimal(vof_string("7.25")), [725, 2], "typed string");
	is(as_decimal(raw_int(42)), undef, "raw int → undef");
	is(as_decimal(raw_str("abc")), undef, "non-numeric string");
};

# ===== as_ratio =====

subtest 'as_ratio' => sub {
	is_deeply(as_ratio(vof_ratio(3, 4)), [3, 4], "typed ratio");
	is_deeply(as_ratio(raw_str("1/3")), [1, 3], "raw string");
	is_deeply(as_ratio(raw_list([raw_int(5), raw_int(8)])),
		[5, 8], "raw list of two ints");
	is_deeply(as_ratio(vof_list([vof_int(5), vof_uint(8)])),
		[5, 8], "typed list of two ints");
	is(as_ratio(raw_str("abc")), undef, "non-ratio string");
	is(as_ratio(raw_list([raw_int(1)])), undef, "list wrong size");
	is(as_ratio(raw_int(42)), undef, "bare int → undef");
};

# ===== as_percent =====

subtest 'as_percent' => sub {
	is_deeply(as_percent(vof_percent(5, 1)), [5, 1], "typed percent");
	is_deeply(as_percent(vof_decimal(5, 1)), [5, 1], "decimal → percent");
	is_deeply(as_percent(raw_str("50%")), [5, 1], "raw string 50%");
	is_deeply(as_percent(raw_str("12.5%")), [125, 3], "raw string 12.5%");
	is_deeply(as_percent(raw_int(50)), [5, 1], "raw int 50 → 0.5");
	is_deeply(as_percent(vof_string("50%")), [5, 1], "typed string 50%");
	is(as_percent(vof_string("50")), undef, "typed string without % → undef");
	is(as_percent(raw_str("50")), undef, "raw string without % → undef");
	is(as_percent(raw_str("%")), undef, "bare % → undef");
	is(as_percent(vof_null()), undef, "null → undef");
};

# ===== as_timestamp =====

subtest 'as_timestamp' => sub {
	is(as_timestamp(vof_timestamp(1700000000)), 1700000000, "typed");
	is(as_timestamp(raw_int(1700000000)), 1700000000, "raw int");
	is(as_timestamp(raw_str("1700000000")), 1700000000, "raw string");
	is(as_timestamp(vof_uint(1700000000)), 1700000000, "typed uint");
	is(as_timestamp(vof_int(1700000000)), 1700000000, "typed int");
	is(as_timestamp(vof_string("1700000000")), 1700000000, "typed string");
	is(as_timestamp(vof_string("abc")), undef, "typed non-numeric string");
	is(as_timestamp(raw_str("abc")), undef, "non-numeric");
	is(as_timestamp(vof_null()), undef, "null → undef");
};

# ===== as_date =====

subtest 'as_date' => sub {
	is_deeply(as_date(vof_date(2025, 6, 15)), [2025, 6, 15], "typed date");
	is_deeply(as_date(vof_datetime(2025, 6, 15, 14, 30)),
		[2025, 6, 15], "datetime → date (truncate)");
	is_deeply(as_date(raw_int(20251231)), [2025, 12, 31], "raw YYYYMMDD int");
	is_deeply(as_date(raw_str("20250101")), [2025, 1, 1], "raw string");
	is_deeply(as_date(raw_list([raw_int(2025), raw_int(6), raw_int(15)])),
		[2025, 6, 15], "raw list of 3 ints");
	is_deeply(as_date(vof_string("20250615")), [2025, 6, 15], "typed string YYYYMMDD");
	is(as_date(vof_string("abc")), undef, "typed non-numeric string");
	is_deeply(as_date(vof_list([vof_int(2025), vof_int(6), vof_int(15)])),
		[2025, 6, 15], "typed list of 3 ints");
	is(as_date(raw_list([raw_int(2025), raw_int(6)])), undef, "list length 2 → undef");
	is(as_date(raw_int(20251301)), undef, "bad month");
	is(as_date(raw_str("abc")), undef, "non-numeric string");
	is(as_date(vof_null()), undef, "null → undef");
};

# ===== as_datetime =====

subtest 'as_datetime' => sub {
	is_deeply(as_datetime(vof_datetime(2025, 6, 15, 14, 30)),
		[2025, 6, 15, 14, 30], "typed datetime");
	is_deeply(as_datetime(vof_date(2025, 6, 15)),
		[2025, 6, 15, 0, 0], "date promoted to midnight");
	is_deeply(as_datetime(raw_int(202512312359)),
		[2025, 12, 31, 23, 59], "raw YYYYMMDDHHMM int");
	is_deeply(as_datetime(
		raw_list([raw_int(2025), raw_int(6), raw_int(15), raw_int(14), raw_int(30)])),
		[2025, 6, 15, 14, 30], "raw list of 5 ints");
	is(as_datetime(raw_int(202512312400)), undef, "bad hour");
	is_deeply(as_datetime(raw_str("202506151430")),
		[2025, 6, 15, 14, 30], "raw string YYYYMMDDHHMM");
	is_deeply(as_datetime(vof_string("202512312359")),
		[2025, 12, 31, 23, 59], "typed string YYYYMMDDHHMM");
	is(as_datetime(vof_string("abc")), undef, "typed non-numeric string");
	is_deeply(as_datetime(
		vof_list([vof_int(2025), vof_int(6), vof_int(15), vof_int(14), vof_int(30)])),
		[2025, 6, 15, 14, 30], "typed list of 5 ints");
	is(as_datetime(raw_list([raw_int(2025), raw_int(6), raw_int(15)])),
		undef, "list length 3 → undef");
	is(as_datetime(vof_null()), undef, "null → undef");
};

# ===== as_timespan =====

subtest 'as_timespan' => sub {
	is_deeply(as_timespan(vof_timespan(24, -1, 0)), [24, -1, 0], "typed");
	is_deeply(as_timespan(raw_list([raw_int(24), raw_int(-1), raw_int(0)])),
		[24, -1, 0], "raw list");
	is(as_timespan(raw_list([raw_int(1), raw_int(2)])), undef, "wrong size");
	is_deeply(as_timespan(vof_list([vof_int(24), vof_int(-1), vof_int(0)])),
		[24, -1, 0], "typed list");
	is(as_timespan(vof_null()), undef, "null → undef");
};

# ===== as_amount =====

subtest 'as_amount' => sub {
	is_deeply(as_amount(vof_amount(125, 1, "USD")), [125, 1, "USD"], "typed");
	is_deeply(as_amount(raw_str("12.5 USD")), [125, 1, "USD"], "string with currency");
	is_deeply(as_amount(raw_str("12.5")), [125, 1, undef], "string bare");
	is_deeply(as_amount(raw_str("0")), [0, 0, undef], "zero string");
	is_deeply(as_amount(vof_string("12.5 USD")), [125, 1, "USD"],
		"typed string with currency");
	is_deeply(as_amount(vof_string("12.5")), [125, 1, undef],
		"typed string bare");
	is_deeply(as_amount(raw_list([raw_str("12.5"), raw_str("USD")])),
		[125, 1, "USD"], "raw list pair");
	is_deeply(as_amount(vof_list([vof_decimal("12.5"), vof_string("USD")])),
		[125, 1, "USD"], "typed list pair");
	is_deeply(as_amount(vof_decimal("12.5")), [125, 1, undef],
		"bare decimal fallback");
	is(as_amount(raw_str("1 2 3")), undef, "string with 3 parts → undef");
	is(as_amount(raw_list([raw_str("1"), raw_str("2"), raw_str("3")])),
		undef, "raw list size 3 → undef (falls through)");
	is(as_amount(vof_list([vof_string("1"), vof_string("2"), vof_string("3")])),
		undef, "typed list size 3 → undef (falls through)");
};

# ===== as_tax =====

subtest 'as_tax' => sub {
	is_deeply(as_tax(vof_tax(125, 1, "GST", "USD")),
		[125, 1, "GST", "USD"], "typed with currency");
	is_deeply(as_tax(vof_tax(125, 1, "GST")),
		[125, 1, "GST", undef], "typed without currency");
	is_deeply(as_tax(raw_str("12.5 GST")),
		[125, 1, "GST", undef], "string: dec tax_code");
	is_deeply(as_tax(raw_str("12.5 USD GST")),
		[125, 1, "GST", "USD"], "string: dec curr tax_code");
	is(as_tax(raw_str("12.5")), undef, "bare decimal → undef");
	is_deeply(as_tax(raw_list([raw_str("12.5"), raw_str("GST")])),
		[125, 1, "GST", undef], "raw list [decimal, tax_code]");
	is_deeply(as_tax(vof_list([vof_decimal("12.5"), vof_string("GST")])),
		[125, 1, "GST", undef], "typed list [decimal, tax_code]");
	is(as_tax(raw_list([raw_str("12.5")])), undef, "list size 1 → undef");
	is_deeply(as_tax(vof_string("12.5 GST")),
		[125, 1, "GST", undef], "typed string: dec tax_code");
	is_deeply(as_tax(vof_string("12.5 USD GST")),
		[125, 1, "GST", "USD"], "typed string: dec curr tax_code");
	is(as_tax(vof_null()), undef, "null → undef");
};

# ===== as_quantity =====

subtest 'as_quantity' => sub {
	is_deeply(as_quantity(vof_quantity(5, 0, "KGM")), [5, 0, "KGM"], "typed");
	is_deeply(as_quantity(raw_str("5 KGM")), [5, 0, "KGM"], "string with unit");
	is_deeply(as_quantity(raw_str("3.5")), [35, 1, undef], "string bare");
};

# ===== as_text =====

subtest 'as_text' => sub {
	my $t = as_text(vof_text({ en => "Hi", fr => "Salut" }));
	is($t->{en}, "Hi", "typed en");
	is($t->{fr}, "Salut", "typed fr");

	# From raw flattened object
	my $raw = raw_list([raw_str("en"), raw_str("Hello")]);
	my $r = as_text($raw);
	is($r->{en}, "Hello", "raw object fallback");
};

# ===== as_ip =====

subtest 'as_ip' => sub {
	my $bytes4 = inet_pton(AF_INET, "192.168.1.1");
	is(as_ip(vof_ip($bytes4)), $bytes4, "typed IPv4 passthrough");
	is(as_ip(raw_str("10.0.0.1")), inet_pton(AF_INET, "10.0.0.1"),
		"string → IPv4 bytes");
	is(as_ip(raw_str("::1")), inet_pton(AF_INET6, "::1"),
		"string → IPv6 bytes");
	is(as_ip(raw_int(42)), undef, "int → undef");
	is(as_ip(vof_data($bytes4)), $bytes4, "data → IPv4 bytes");
	is(as_ip(vof_string("10.0.0.1")), inet_pton(AF_INET, "10.0.0.1"),
		"typed string → IPv4 bytes");
};

# ===== as_subnet =====

subtest 'as_subnet' => sub {
	my $bytes4 = inet_pton(AF_INET, "10.0.0.0");
	is_deeply(as_subnet(vof_subnet($bytes4, 8)), [$bytes4, 8], "typed");
	my $r = as_subnet(raw_str("192.168.0.0/16"));
	is($r->[1], 16, "CIDR prefix length");
	is(length($r->[0]), 4, "IPv4 bytes");
	is(as_subnet(raw_str("10.0.0.0/33")), undef, "prefix > 32 for IPv4");
	is(as_subnet(raw_str("invalid")), undef, "bad string");
	my $s2 = as_subnet(raw_list([raw_str("10.0.0.0"), raw_int(8)]));
	is($s2->[0], $bytes4, "raw list IP");
	is($s2->[1], 8, "raw list prefix");
	my $s3 = as_subnet(vof_list([vof_ip($bytes4), vof_uint(8)]));
	is($s3->[0], $bytes4, "typed list IP");
	is($s3->[1], 8, "typed list prefix");
	my $s4 = as_subnet(vof_string("192.168.0.0/16"));
	is($s4->[1], 16, "typed string prefix len");
	is(as_subnet(raw_list([raw_str("10.0.0.0")])), undef,
		"raw list size 1 → undef");
	is(as_subnet(vof_list([vof_ip($bytes4)])), undef,
		"typed list size 1 → undef");
	is(as_subnet(vof_null()), undef, "null → undef");
};

# ===== as_coords =====

subtest 'as_coords' => sub {
	is_deeply(as_coords(vof_coords(45.5, -73.5)), [45.5, -73.5], "typed");
	my $r = as_coords(raw_list([raw_int(45), raw_int(-73)]));
	is_deeply($r, [45.0, -73.0], "raw list of ints → floats");
	is(as_coords(raw_list([raw_int(1)])), undef, "wrong size");
	is_deeply(as_coords(vof_list([vof_float(45.5), vof_float(-73.5)])),
		[45.5, -73.5], "typed list of floats");
	is(as_coords(vof_null()), undef, "null → undef");
};

# ===== as_strmap =====

subtest 'as_strmap' => sub {
	my $m = vof_strmap({ a => vof_int(1), b => vof_int(2) });
	my $r = as_strmap($m, \&as_int);
	is_deeply($r, { a => 1, b => 2 }, "typed strmap");

	# From raw flattened list
	my $raw = raw_list([raw_str("x"), raw_int(10), raw_str("y"), raw_int(20)]);
	$r = as_strmap($raw, \&as_int);
	is_deeply($r, { x => 10, y => 20 }, "raw list pairs");

	# Odd-length list fails
	is(as_strmap(raw_list([raw_str("a")]), \&as_int), undef, "odd list → undef");

	# Typed list pairs
	my $tl = vof_list([vof_string("x"), vof_int(10), vof_string("y"), vof_int(20)]);
	$r = as_strmap($tl, \&as_int);
	is_deeply($r, { x => 10, y => 20 }, "typed list pairs");

	# Unhandled type
	is(as_strmap(vof_int(42), \&as_int), undef, "int → undef");
};

# ===== as_uintmap =====

subtest 'as_uintmap' => sub {
	my $m = vof_uintmap({ 0 => vof_string("a"), 1 => vof_string("b") });
	my $r = as_uintmap($m, \&as_string);
	is($r->{0}, "a", "typed uintmap key 0");
	is($r->{1}, "b", "typed uintmap key 1");

	my $raw = raw_list([raw_int(5), raw_str("five"), raw_int(10), raw_str("ten")]);
	$r = as_uintmap($raw, \&as_string);
	is_deeply($r, { 5 => "five", 10 => "ten" }, "raw list pairs");

	# Typed list pairs
	my $tl = vof_list([vof_int(5), vof_string("five"), vof_int(10), vof_string("ten")]);
	$r = as_uintmap($tl, \&as_string);
	is_deeply($r, { 5 => "five", 10 => "ten" }, "typed list pairs");

	# Unhandled type
	is(as_uintmap(vof_int(42), \&as_string), undef, "int → undef");
};

# ===== as_list =====

subtest 'as_list' => sub {
	my $l = vof_list([vof_int(1), vof_int(2), vof_int(3)]);
	is_deeply(as_list($l, \&as_int), [1, 2, 3], "typed list");

	my $raw = raw_list([raw_int(10), raw_int(20)]);
	is_deeply(as_list($raw, \&as_int), [10, 20], "raw list");

	# Reader failure propagates
	my $bad = raw_list([raw_int(1), raw_str("abc")]);
	is(as_list($bad, \&as_int), undef, "reader failure → undef");

	# Unhandled type
	is(as_list(vof_int(42), \&as_int), undef, "int → undef");
};

# ===== as_ndarray =====

subtest 'as_ndarray' => sub {
	my $nd = vof_ndarray([2, 3], [map { vof_int($_) } 1..6]);
	my $r = as_ndarray($nd, \&as_int);
	is_deeply($r->[0], [2, 3], "shape");
	is_deeply($r->[1], [1, 2, 3, 4, 5, 6], "values");

	# From raw: [[sizes], val, val, ...]
	my $raw = raw_list([
		raw_list([raw_int(2), raw_int(2)]),
		raw_int(1), raw_int(2), raw_int(3), raw_int(4),
	]);
	$r = as_ndarray($raw, \&as_int);
	is_deeply($r->[0], [2, 2], "raw shape");
	is_deeply($r->[1], [1, 2, 3, 4], "raw values");

	# Typed list
	my $tl = vof_list([
		vof_list([vof_int(2), vof_int(2)]),
		vof_int(10), vof_int(20), vof_int(30), vof_int(40),
	]);
	$r = as_ndarray($tl, \&as_int);
	is_deeply($r->[0], [2, 2], "typed list shape");
	is_deeply($r->[1], [10, 20, 30, 40], "typed list values");

	# Unhandled type
	is(as_ndarray(vof_int(42), \&as_int), undef, "int → undef");
};

# ===== as_variant =====

subtest 'as_variant' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $schema = $ctx->schema("status");

	# Typed enum
	my $e = vof_enum($schema, "Draft");
	my $got;
	as_variant($ctx, $schema, $e, sub { $got = [$_[0], $_[1]]; return 1 });
	is($got->[0], "Draft", "typed enum name");
	is_deeply($got->[1], [], "typed enum no args");

	# Typed variant with args
	my $va = vof_variant($schema, "Shipped", vof_int(42));
	as_variant($ctx, $schema, $va, sub { $got = [$_[0], $_[1]]; return 1 });
	is($got->[0], "Shipped", "typed variant name");
	is(scalar @{$got->[1]}, 1, "typed variant one arg");

	# Bare string
	as_variant($ctx, $schema, raw_str("Confirmed"), sub {
		$got = $_[0]; return 1
	});
	is($got, "Confirmed", "bare string");

	# Bare integer → symbol lookup
	as_variant($ctx, $schema, raw_int(0), sub {
		$got = $_[0]; return 1
	});
	is($got, "Draft", "bare int 0 → Draft");

	# List: [name_string, args...]
	as_variant($ctx, $schema, raw_list([raw_str("Shipped"), raw_int(99)]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Shipped", "list variant name");
	is(scalar @{$got->[1]}, 1, "list variant args");

	# List with integer ID (raw_int) as first element → _resolve_variant_id
	as_variant($ctx, $schema, raw_list([raw_int(0), raw_int(99)]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Draft", "list with raw_int ID → symbol lookup");
	is(scalar @{$got->[1]}, 1, "list with raw_int ID args");

	# List with typed int ID → _resolve_variant_id VOF_INT path
	as_variant($ctx, $schema, raw_list([vof_int(1), raw_str("x")]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Confirmed", "list with vof_int ID → symbol lookup");

	# List with typed uint ID → _resolve_variant_id VOF_UINT path
	as_variant($ctx, $schema, raw_list([vof_uint(2)]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Shipped", "list with vof_uint ID → symbol lookup");

	# List with vof_string ID → _resolve_variant_id VOF_STRING path
	as_variant($ctx, $schema, raw_list([vof_string("Delivered")]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Delivered", "list with vof_string ID");

	# Typed list (VOF_LIST) variant
	as_variant($ctx, $schema,
		vof_list([vof_string("Draft"), vof_int(7)]), sub {
		$got = [$_[0], $_[1]]; return 1
	});
	is($got->[0], "Draft", "typed list variant name");
	is(scalar @{$got->[1]}, 1, "typed list variant args");

	# Typed VOF_INT → bare integer symbol lookup
	as_variant($ctx, $schema, vof_int(0), sub {
		$got = $_[0]; return 1
	});
	is($got, "Draft", "typed vof_int(0) → Draft");

	# Typed VOF_UINT → bare integer symbol lookup
	as_variant($ctx, $schema, vof_uint(1), sub {
		$got = $_[0]; return 1
	});
	is($got, "Confirmed", "typed vof_uint(1) → Confirmed");

	# Unknown int
	my $r = as_variant($ctx, $schema, raw_int(999), sub { return 1 });
	is($r, undef, "unknown int → undef");

	# Unhandled type → final return undef
	$r = as_variant($ctx, $schema, vof_float(1.5), sub { return 1 });
	is($r, undef, "float → undef (unhandled type)");
};

# ===== as_record =====

subtest 'as_record' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $schema = $ctx->schema("order");

	# Typed record
	my $rec = vof_record($schema, {
		id    => vof_int(1),
		total => vof_decimal("99.99"),
	});
	my $r = as_record($ctx, $schema, $rec, sub {
		my ($f) = @_;
		return { id => as_int($f->{id}), total => as_decimal($f->{total}) };
	});
	is($r->{id}, 1, "typed record id");
	is_deeply($r->{total}, [9999, 2], "typed record total");

	# Raw flattened list (from JSON decode of object)
	my $raw = raw_list([
		raw_str("id"), raw_int(42),
		raw_str("customer"), raw_str("Acme"),
	]);
	$r = as_record($ctx, $schema, $raw, sub {
		my ($f) = @_;
		return {
			id       => as_int($f->{id}),
			customer => as_string($f->{customer}),
		};
	});
	is($r->{id}, 42, "raw record id");
	is($r->{customer}, "Acme", "raw record customer");

	# Odd-length list fails
	$r = as_record($ctx, $schema, raw_list([raw_str("id")]), sub { return {} });
	is($r, undef, "odd list → undef");

	# Unhandled type → final return undef
	$r = as_record($ctx, $schema, vof_string("hi"), sub { return {} });
	is($r, undef, "string → undef (unhandled type)");
};

# ===== as_series =====

subtest 'as_series' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $schema = $ctx->schema("order.line");

	# Typed series
	my $s = vof_series($schema, [
		{ i => vof_int(1), qty => vof_decimal("2.0") },
		{ i => vof_int(2), qty => vof_decimal("3.5") },
	]);
	my $r = as_series($ctx, $schema, $s, sub {
		my ($f) = @_;
		return { i => as_int($f->{i}), qty => as_decimal($f->{qty}) };
	});
	is(scalar @$r, 2, "two rows");
	is($r->[0]{i}, 1, "first row i");
	is_deeply($r->[1]{qty}, [35, 1], "second row qty");

	# Raw JSON wire format: [header_row, data_row, ...]
	my $raw = raw_list([
		raw_list([raw_str("i"), raw_str("product")]),
		raw_list([raw_int(1), raw_str("Widget")]),
		raw_list([raw_int(2), raw_str("Gadget")]),
	]);
	$r = as_series($ctx, $schema, $raw, sub {
		my ($f) = @_;
		return { i => as_int($f->{i}), product => as_string($f->{product}) };
	});
	is(scalar @$r, 2, "raw: two rows");
	is($r->[0]{product}, "Widget", "raw: first product");
	is($r->[1]{i}, 2, "raw: second i");

	# Empty series
	$r = as_series($ctx, $schema, raw_list([]), sub { die "should not be called" });
	is_deeply($r, [], "empty series → []");

	# Unhandled type → final return undef
	$r = as_series($ctx, $schema, vof_string("hi"), sub { return {} });
	is($r, undef, "string → undef (unhandled type)");
};

done_testing;
