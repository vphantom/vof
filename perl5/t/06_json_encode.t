use strict;
use warnings;
use Test::More;
use Socket qw(AF_INET AF_INET6 inet_pton inet_ntop);
use JSON ();
use VOF qw(:constructors :constants :helpers);
use VOF::JSON;

# ===== Scalars =====

subtest 'null' => sub {
	is(VOF::JSON::encode(vof_null()), undef, "null → undef");
};

subtest 'bool' => sub {
	is(VOF::JSON::encode(vof_bool(1)), JSON::true, "true");
	is(VOF::JSON::encode(vof_bool(0)), JSON::false, "false");
};

subtest 'int' => sub {
	is(VOF::JSON::encode(vof_int(42)), 42, "positive int");
	is(VOF::JSON::encode(vof_int(-7)), -7, "negative int");
	is(VOF::JSON::encode(vof_int(0)), 0, "zero");
};

subtest 'int safe range' => sub {
	# Integers outside JS safe range become strings
	my $big = 9_007_199_254_740_992;  # MAX_SAFE_INTEGER + 1
	is(VOF::JSON::encode(vof_int($big)), "$big", "large int → string");
};

subtest 'uint' => sub {
	is(VOF::JSON::encode(vof_uint(100)), 100, "uint");
};

subtest 'float' => sub {
	my $e = VOF::JSON::encode(vof_float(3.14));
	ok(abs($e - 3.14) < 1e-10, "float value");
};

subtest 'string' => sub {
	is(VOF::JSON::encode(vof_string("hello")), "hello", "string");
};

subtest 'data' => sub {
	my $e = VOF::JSON::encode(vof_data("\x00\x01\x02"));
	ok(defined $e && length($e) > 0, "data → base64url string");
	# Verify round-trip
	use MIME::Base64 qw(decode_base64url);
	is(decode_base64url($e), "\x00\x01\x02", "base64url round-trip");
};

# ===== Numeric types =====

subtest 'decimal' => sub {
	is(VOF::JSON::encode(vof_decimal("12.50")), "12.5", "trailing zero stripped");
	is(VOF::JSON::encode(vof_decimal(0, 0)), "0", "zero");
	is(VOF::JSON::encode(vof_decimal("-5.25")), "-5.25", "negative");
};

subtest 'ratio' => sub {
	is(VOF::JSON::encode(vof_ratio(3, 4)), "3/4", "ratio");
	is(VOF::JSON::encode(vof_ratio(-1, 3)), "-1/3", "negative ratio");
};

subtest 'percent' => sub {
	is(VOF::JSON::encode(vof_percent("50%")), "50%", "50%");
	is(VOF::JSON::encode(vof_percent("12.5%")), "12.5%", "12.5%");
	is(VOF::JSON::encode(vof_percent("100%")), "100%", "100%");
};

# ===== Temporal types =====

subtest 'timestamp' => sub {
	is(VOF::JSON::encode(vof_timestamp(1700000000)), 1700000000, "timestamp");
};

subtest 'date' => sub {
	is(VOF::JSON::encode(vof_date(2025, 12, 31)), 20251231, "date");
	is(VOF::JSON::encode(vof_date(2025, 1, 1)), 20250101, "date Jan 1");
};

subtest 'datetime' => sub {
	is(VOF::JSON::encode(vof_datetime(2025, 12, 31, 23, 59)),
		202512312359, "datetime");
};

subtest 'timespan' => sub {
	is_deeply(VOF::JSON::encode(vof_timespan(24, -1, 0)),
		[24, -1, 0], "timespan");
};

# ===== Code types =====

subtest 'code types' => sub {
	is(VOF::JSON::encode(vof_code("ABC")), "ABC", "code");
	is(VOF::JSON::encode(vof_language("en")), "en", "language");
	is(VOF::JSON::encode(vof_country("CA")), "CA", "country");
	is(VOF::JSON::encode(vof_subdivision("QC")), "QC", "subdivision");
	is(VOF::JSON::encode(vof_currency("USD")), "USD", "currency");
	is(VOF::JSON::encode(vof_tax_code("CA_GST")), "CA_GST", "tax_code");
	is(VOF::JSON::encode(vof_unit("KGM")), "KGM", "unit");
};

# ===== Text =====

subtest 'text' => sub {
	my $e = VOF::JSON::encode(vof_text({ en => "Hi", fr => "Salut" }));
	is(ref $e, "HASH", "text → hash");
	is($e->{en}, "Hi", "en");
	is($e->{fr}, "Salut", "fr");
};

# ===== Qualified decimals =====

subtest 'amount' => sub {
	is(VOF::JSON::encode(vof_amount(125, 1, "USD")), "12.5 USD", "with currency");
	is(VOF::JSON::encode(vof_amount(125, 1)), "12.5", "without currency");
};

subtest 'tax' => sub {
	is(VOF::JSON::encode(vof_tax(125, 1, "GST")), "12.5 GST", "tax without currency");
	is(VOF::JSON::encode(vof_tax(125, 1, "GST", "USD")),
		"12.5 USD GST", "tax with currency");
};

subtest 'quantity' => sub {
	is(VOF::JSON::encode(vof_quantity(5, 0, "KGM")), "5 KGM", "with unit");
	is(VOF::JSON::encode(vof_quantity(35, 1)), "3.5", "without unit");
};

# ===== Network types =====

subtest 'ip' => sub {
	my $bytes4 = inet_pton(AF_INET, "192.168.1.1");
	is(VOF::JSON::encode(vof_ip($bytes4)), "192.168.1.1", "IPv4");

	my $bytes6 = inet_pton(AF_INET6, "::1");
	my $e = VOF::JSON::encode(vof_ip($bytes6));
	is($e, "::1", "IPv6 loopback");
};

subtest 'subnet' => sub {
	my $bytes4 = inet_pton(AF_INET, "10.0.0.0");
	is(VOF::JSON::encode(vof_subnet($bytes4, 8)), "10.0.0.0/8", "CIDR");
};

subtest 'coords' => sub {
	my $e = VOF::JSON::encode(vof_coords(45.5, -73.5));
	is(ref $e, "ARRAY", "coords → array");
	ok(abs($e->[0] - 45.5) < 1e-6, "lat");
	ok(abs($e->[1] - (-73.5)) < 1e-6, "lon");
};

# ===== Collections =====

subtest 'strmap' => sub {
	my $e = VOF::JSON::encode(vof_strmap({
		a => vof_int(1), b => vof_string("two")
	}));
	is(ref $e, "HASH", "strmap → hash");
	is($e->{a}, 1, "int value");
	is($e->{b}, "two", "string value");
};

subtest 'uintmap' => sub {
	my $e = VOF::JSON::encode(vof_uintmap({
		0 => vof_string("zero"), 1 => vof_string("one")
	}));
	is(ref $e, "HASH", "uintmap → hash");
	is($e->{0}, "zero", "key 0");
};

subtest 'list' => sub {
	my $e = VOF::JSON::encode(vof_list([vof_int(1), vof_string("two")]));
	is_deeply($e, [1, "two"], "list → array");
};

subtest 'ndarray' => sub {
	my $e = VOF::JSON::encode(vof_ndarray([2, 3],
		[map { vof_int($_) } 1..6]));
	is_deeply($e->[0], [2, 3], "shape");
	is(scalar(@$e), 7, "shape + 6 values");
	is($e->[1], 1, "first value");
	is($e->[6], 6, "last value");
};

# ===== Structured types =====

subtest 'enum' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("status", keys => [], required => []);
	is(VOF::JSON::encode(vof_enum($s, "Draft")), "Draft", "enum → string");
};

subtest 'variant' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("status", keys => [], required => []);
	my $e = VOF::JSON::encode(vof_variant($s, "Error", vof_string("oops")));
	is_deeply($e, ["Error", "oops"], "variant → [name, args...]");
};

subtest 'record' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("order", keys => ["id"], required => []);
	my $e = VOF::JSON::encode(vof_record($s, {
		id => vof_int(1), total => vof_decimal("99.99"),
	}));
	is(ref $e, "HASH", "record → hash");
	is($e->{id}, 1, "id field");
	is($e->{total}, "99.99", "total field");
};

subtest 'series' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $s = $ctx->schema("order.line");

	my $e = VOF::JSON::encode(vof_series($s, [
		{ i => vof_int(1), qty => vof_decimal("2.5") },
		{ i => vof_int(2), qty => vof_decimal("3.0") },
	]), $ctx);
	is(ref $e, "ARRAY", "series → array");
	is(scalar @$e, 3, "header + 2 rows");
	# Header should be sorted by symbol ID: i=0, qty=2
	is($e->[0][0], "i", "header first col");
	is($e->[0][1], "qty", "header second col");
	# Data rows
	is($e->[1][0], 1, "row 1 i");
	is($e->[1][1], "2.5", "row 1 qty");
};

subtest 'empty series' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("thing", keys => ["id"], required => []);
	my $e = VOF::JSON::encode(vof_series($s, []));
	is_deeply($e, [], "empty series → []");
};

subtest 'encode raw types croaks' => sub {
	my $raw = VOF::Value->new(VOF_RAW_TLIST, []);
	eval { VOF::JSON::encode($raw) };
	like($@, qr/raw types.*cannot be encoded/, "RAW_TLIST croaks");
};

done_testing;
