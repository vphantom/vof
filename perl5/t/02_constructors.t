use strict;
use warnings;
use Test::More;
use Socket qw(AF_INET inet_pton);
use VOF qw(:constructors :constants);

# ===== Singletons =====

subtest 'singletons' => sub {
	my $n = vof_null();
	isa_ok($n, 'VOF::Value');
	is($n->[0], VOF_NULL, "null type tag");
	is(vof_null(), $n, "null is singleton");

	my $t = vof_bool(1);
	is($t->[0], VOF_BOOL, "true type tag");
	is($t->[1], 1, "true value");
	is(vof_bool("yes"), $t, "true is singleton");

	my $f = vof_bool(0);
	is($f->[0], VOF_BOOL, "false type tag");
	is($f->[1], 0, "false value");
	is(vof_bool(""), $f, "false is singleton");
	is(vof_bool(undef), $f, "undef → false singleton");
};

# ===== Scalar constructors =====

subtest 'vof_int' => sub {
	my $v = vof_int(42);
	is($v->[0], VOF_INT, "type tag");
	is($v->[1], 42, "value");

	$v = vof_int(-7);
	is($v->[1], -7, "negative");

	eval { vof_int(undef) };
	like($@, qr/value required/, "undef croaks");
};

subtest 'vof_uint' => sub {
	my $v = vof_uint(0);
	is($v->[0], VOF_UINT, "type tag");
	is($v->[1], 0, "zero");

	eval { vof_uint(-1) };
	like($@, qr/non-negative/, "negative croaks");

	eval { vof_uint(undef) };
	like($@, qr/value required/, "undef croaks");
};

subtest 'vof_float' => sub {
	my $v = vof_float(3.14);
	is($v->[0], VOF_FLOAT, "type tag");
	ok(abs($v->[1] - 3.14) < 1e-10, "value");

	eval { vof_float(undef) };
	like($@, qr/value required/, "undef croaks");
};

subtest 'vof_string' => sub {
	my $v = vof_string("hello");
	is($v->[0], VOF_STRING, "type tag");
	is($v->[1], "hello", "value");

	eval { vof_string(undef) };
	like($@, qr/value required/, "undef croaks");
};

subtest 'vof_data' => sub {
	my $v = vof_data("\x00\x01\x02");
	is($v->[0], VOF_DATA, "type tag");
	is($v->[1], "\x00\x01\x02", "bytes");

	eval { vof_data(undef) };
	like($@, qr/value required/, "undef croaks");
};

# ===== Numeric constructors =====

subtest 'vof_decimal' => sub {
	# From string
	my $v = vof_decimal("12.50");
	is($v->[0], VOF_DECIMAL, "type tag");
	is($v->[1], 125, "significand");
	is($v->[2], 1, "places (trailing zero stripped)");

	# From components
	$v = vof_decimal(1250, 2);
	is($v->[1], 125, "optimized sig");
	is($v->[2], 1, "optimized places");

	eval { vof_decimal("abc") };
	like($@, qr/invalid decimal/, "bad string croaks");

	eval { vof_decimal(1, 10) };
	like($@, qr/places must be 0\.\.9/, "places > 9 croaks");
};

subtest 'vof_ratio' => sub {
	my $v = vof_ratio(3, 4);
	is($v->[0], VOF_RATIO, "type tag");
	is($v->[1], 3, "numerator");
	is($v->[2], 4, "denominator");

	eval { vof_ratio(1, 0) };
	like($@, qr/denominator must be positive/, "zero denominator croaks");
};

subtest 'vof_percent' => sub {
	# From string
	my $v = vof_percent("50%");
	is($v->[0], VOF_PERCENT, "type tag");
	is($v->[1], 5, "sig (0.5)");
	is($v->[2], 1, "places");

	# From components
	$v = vof_percent(5, 1);
	is($v->[1], 5, "sig from components");
	is($v->[2], 1, "places from components");

	eval { vof_percent("abc%") };
	like($@, qr/invalid percent/, "bad string croaks");
};

# ===== Temporal constructors =====

subtest 'vof_timestamp' => sub {
	my $v = vof_timestamp(1700000000);
	is($v->[0], VOF_TIMESTAMP, "type tag");
	is($v->[1], 1700000000, "epoch");

	eval { vof_timestamp(undef) };
	like($@, qr/value required/, "undef croaks");
};

subtest 'vof_date' => sub {
	my $v = vof_date(2025, 6, 15);
	is($v->[0], VOF_DATE, "type tag");
	is($v->[1], 2025, "year");
	is($v->[2], 6, "month");
	is($v->[3], 15, "day");

	eval { vof_date(2025, 0, 1) };
	like($@, qr/month must be 1\.\.12/, "month 0 croaks");

	eval { vof_date(2025, 13, 1) };
	like($@, qr/month must be 1\.\.12/, "month 13 croaks");

	eval { vof_date(2025, 1, 0) };
	like($@, qr/day must be 1\.\.31/, "day 0 croaks");

	eval { vof_date(2025, 1, 32) };
	like($@, qr/day must be 1\.\.31/, "day 32 croaks");
};

subtest 'vof_datetime' => sub {
	my $v = vof_datetime(2025, 6, 15, 14, 30);
	is($v->[0], VOF_DATETIME, "type tag");
	is($v->[1], 2025, "year");
	is($v->[4], 14, "hour");
	is($v->[5], 30, "minute");

	eval { vof_datetime(2025, 6, 15, 24, 0) };
	like($@, qr/hour must be 0\.\.23/, "hour 24 croaks");

	eval { vof_datetime(2025, 6, 15, 0, 60) };
	like($@, qr/minute must be 0\.\.59/, "minute 60 croaks");
};

subtest 'vof_timespan' => sub {
	my $v = vof_timespan(24, -1, 0);
	is($v->[0], VOF_TIMESPAN, "type tag");
	is($v->[1], 24, "half-months");
	is($v->[2], -1, "days");
	is($v->[3], 0, "seconds");

	eval { vof_timespan(undef, 0, 0) };
	like($@, qr/three arguments required/, "undef croaks");
};

# ===== Code constructors =====

subtest 'code constructors' => sub {
	my @codes = (
		[\&vof_code,        VOF_CODE,        "ABC"],
		[\&vof_language,    VOF_LANGUAGE,    "en"],
		[\&vof_country,     VOF_COUNTRY,     "CA"],
		[\&vof_subdivision, VOF_SUBDIVISION, "QC"],
		[\&vof_currency,    VOF_CURRENCY,    "USD"],
		[\&vof_tax_code,    VOF_TAX_CODE,    "CA_QC_TVQ"],
		[\&vof_unit,        VOF_UNIT,        "KGM"],
	);
	for my $case (@codes) {
		my ($fn, $tag, $str) = @$case;
		my $v = $fn->($str);
		is($v->[0], $tag, "tag for $str");
		is($v->[1], $str, "value for $str");
	}

	eval { vof_code(undef) };
	like($@, qr/string required/, "undef croaks");
};

# ===== Text constructor =====

subtest 'vof_text' => sub {
	my $v = vof_text({ en => "Hello", fr => "Bonjour" });
	is($v->[0], VOF_TEXT, "type tag");
	is($v->[1]{en}, "Hello", "en");
	is($v->[1]{fr}, "Bonjour", "fr");

	eval { vof_text("not a hash") };
	like($@, qr/hashref required/, "non-hash croaks");
};

# ===== Qualified decimal constructors =====

subtest 'vof_amount' => sub {
	my $v = vof_amount(1250, 2, "USD");
	is($v->[0], VOF_AMOUNT, "type tag");
	is($v->[1], 125, "optimized sig");
	is($v->[2], 1, "optimized places");
	is($v->[3], "USD", "currency");

	$v = vof_amount(500, 0);
	is($v->[3], undef, "currency optional");
};

subtest 'vof_tax' => sub {
	my $v = vof_tax(125, 1, "CA_GST", "CAD");
	is($v->[0], VOF_TAX, "type tag");
	is($v->[3], "CA_GST", "tax_code");
	is($v->[4], "CAD", "currency");

	eval { vof_tax(1, 0, undef) };
	like($@, qr/tax_code required/, "missing tax_code croaks");
};

subtest 'vof_quantity' => sub {
	my $v = vof_quantity(5, 0, "KGM");
	is($v->[0], VOF_QUANTITY, "type tag");
	is($v->[1], 5, "sig");
	is($v->[3], "KGM", "unit");

	$v = vof_quantity(3, 0);
	is($v->[3], undef, "unit optional");
};

# ===== Network constructors =====

subtest 'vof_ip' => sub {
	my $bytes4 = inet_pton(AF_INET, "192.168.1.1");
	my $v = vof_ip($bytes4);
	is($v->[0], VOF_IP, "type tag");
	is(length($v->[1]), 4, "IPv4 bytes");

	eval { vof_ip("abc") };
	like($@, qr/must be 4 or 16 bytes/, "bad length croaks");
};

subtest 'vof_subnet' => sub {
	my $bytes4 = inet_pton(AF_INET, "10.0.0.0");
	my $v = vof_subnet($bytes4, 8);
	is($v->[0], VOF_SUBNET, "type tag");
	is($v->[2], 8, "prefix length");
};

subtest 'vof_coords' => sub {
	my $v = vof_coords(45.5017, -73.5673);
	is($v->[0], VOF_COORDS, "type tag");
	ok(abs($v->[1] - 45.5017) < 1e-6, "lat");
	ok(abs($v->[2] - (-73.5673)) < 1e-6, "lon");
};

# ===== Collection constructors =====

subtest 'vof_strmap' => sub {
	my $v = vof_strmap({ a => vof_int(1), b => vof_int(2) });
	is($v->[0], VOF_STRMAP, "type tag");
	is($v->[1]{a}[1], 1, "value a");

	eval { vof_strmap({ a => 1 }) };
	like($@, qr/VOF::Value/, "non-Value croaks");
};

subtest 'vof_uintmap' => sub {
	my $v = vof_uintmap({ 0 => vof_string("x"), 1 => vof_string("y") });
	is($v->[0], VOF_UINTMAP, "type tag");

	eval { vof_uintmap({ "-1" => vof_int(0) }) };
	like($@, qr/non-negative/, "negative key croaks");
};

subtest 'vof_list' => sub {
	my $v = vof_list([vof_int(1), vof_string("two")]);
	is($v->[0], VOF_LIST, "type tag");
	is(scalar @{$v->[1]}, 2, "length");
};

subtest 'vof_ndarray' => sub {
	my $v = vof_ndarray([2, 3], [map { vof_int($_) } 1..6]);
	is($v->[0], VOF_NDARRAY, "type tag");
	is_deeply($v->[1], [2, 3], "shape");
	is(scalar @{$v->[2]}, 6, "values count");

	eval { vof_ndarray([2, 3], [map { vof_int($_) } 1..5]) };
	like($@, qr/expected 6/, "wrong count croaks");
};

# ===== Structured constructors =====

subtest 'vof_enum' => sub {
	my $ctx = VOF::Context->new("test");
	my $schema = $ctx->schema("status", keys => [], required => []);
	my $v = vof_enum($schema, "Draft");
	is($v->[0], VOF_ENUM, "type tag");
	is($v->[2], "Draft", "name");
};

subtest 'vof_variant' => sub {
	my $ctx = VOF::Context->new("test");
	my $schema = $ctx->schema("status", keys => [], required => []);
	my $v = vof_variant($schema, "Error", vof_string("oops"));
	is($v->[0], VOF_VARIANT, "type tag");
	is($v->[2], "Error", "name");
	is(scalar @{$v->[3]}, 1, "one arg");
};

subtest 'vof_record' => sub {
	my $ctx = VOF::Context->new("test");
	my $schema = $ctx->schema("thing", keys => ["id"], required => []);
	my $v = vof_record($schema, { id => vof_int(1), name => vof_string("x") });
	is($v->[0], VOF_RECORD, "type tag");
	is($v->[2]{id}[1], 1, "field id");
};

subtest 'vof_series' => sub {
	my $ctx = VOF::Context->new("test");
	my $schema = $ctx->schema("thing", keys => ["id"], required => []);
	my $v = vof_series($schema, [
		{ id => vof_int(1), name => vof_string("a") },
		{ id => vof_int(2), name => vof_string("b") },
	]);
	is($v->[0], VOF_SERIES, "type tag");
	is(scalar @{$v->[2]}, 2, "two records");
};

done_testing;
