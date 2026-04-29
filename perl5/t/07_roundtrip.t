use strict;
use warnings;
use Test::More;
use JSON ();
use Socket qw(AF_INET inet_pton);
use VOF qw(:constructors :readers :constants :helpers);
use VOF::JSON;

# Helper: VOF value → JSON string → Perl → raw VOF → reader
sub roundtrip_via_json {
	my ($val) = @_;
	my $encoded  = VOF::JSON::encode($val);
	my $json_str = JSON::encode_json(ref $encoded ? $encoded : [$encoded]);
	my $decoded  = JSON::decode_json($json_str);
	# Unwrap if we wrapped a scalar
	$decoded = $decoded->[0] unless ref $encoded;
	return VOF::JSON::decode($decoded);
}

# ===== Scalars =====

subtest 'null round-trip' => sub {
	my $r = roundtrip_via_json(vof_null());
	is($r->[0], VOF_NULL, "null preserved");
};

subtest 'bool round-trip' => sub {
	my $t = roundtrip_via_json(vof_bool(1));
	is(as_bool($t), 1, "true preserved");

	my $f = roundtrip_via_json(vof_bool(0));
	is(as_bool($f), 0, "false preserved");
};

subtest 'int round-trip' => sub {
	my $r = roundtrip_via_json(vof_int(42));
	is(as_int($r), 42, "positive int");

	$r = roundtrip_via_json(vof_int(-7));
	is(as_int($r), -7, "negative int");

	$r = roundtrip_via_json(vof_int(0));
	is(as_int($r), 0, "zero");
};

subtest 'uint round-trip' => sub {
	my $r = roundtrip_via_json(vof_uint(999));
	is(as_uint($r), 999, "uint preserved");
};

subtest 'float round-trip' => sub {
	my $r = roundtrip_via_json(vof_float(3.14));
	ok(abs(as_float($r) - 3.14) < 1e-10, "float preserved");
};

subtest 'string round-trip' => sub {
	my $r = roundtrip_via_json(vof_string("hello world"));
	is(as_string($r), "hello world", "string preserved");
};

# ===== Numeric types =====

subtest 'decimal round-trip' => sub {
	my $r = roundtrip_via_json(vof_decimal("12.50"));
	is_deeply(as_decimal($r), [125, 1], "12.50 preserved");

	$r = roundtrip_via_json(vof_decimal("-0.5"));
	is_deeply(as_decimal($r), [-5, 1], "-0.5 preserved");

	$r = roundtrip_via_json(vof_decimal(0, 0));
	is_deeply(as_decimal($r), [0, 0], "zero decimal");
};

subtest 'ratio round-trip' => sub {
	my $r = roundtrip_via_json(vof_ratio(3, 4));
	is_deeply(as_ratio($r), [3, 4], "3/4 preserved");
};

subtest 'percent round-trip' => sub {
	my $r = roundtrip_via_json(vof_percent("50%"));
	# Encoded as "50%", decoded as RAW_TSTR, read by as_percent
	is_deeply(as_percent($r), [5, 1], "50% preserved as 0.5");

	$r = roundtrip_via_json(vof_percent("12.5%"));
	is_deeply(as_percent($r), [125, 3], "12.5% preserved");
};

# ===== Temporal types =====

subtest 'timestamp round-trip' => sub {
	my $r = roundtrip_via_json(vof_timestamp(1700000000));
	is(as_timestamp($r), 1700000000, "timestamp preserved");
};

subtest 'date round-trip' => sub {
	my $r = roundtrip_via_json(vof_date(2025, 12, 31));
	is_deeply(as_date($r), [2025, 12, 31], "date preserved");
};

subtest 'datetime round-trip' => sub {
	my $r = roundtrip_via_json(vof_datetime(2025, 6, 15, 14, 30));
	is_deeply(as_datetime($r), [2025, 6, 15, 14, 30], "datetime preserved");
};

subtest 'timespan round-trip' => sub {
	my $r = roundtrip_via_json(vof_timespan(24, -1, 3600));
	is_deeply(as_timespan($r), [24, -1, 3600], "timespan preserved");
};

# ===== Code types =====

subtest 'code types round-trip' => sub {
	for my $pair (
		[vof_language("en"),          \&as_language,    "en"],
		[vof_country("CA"),           \&as_country,     "CA"],
		[vof_currency("USD"),         \&as_currency,    "USD"],
		[vof_unit("KGM"),             \&as_unit,        "KGM"],
		[vof_tax_code("CA_QC_TVQ"),   \&as_tax_code,    "CA_QC_TVQ"],
		[vof_subdivision("QC"),       \&as_subdivision, "QC"],
	) {
		my ($val, $reader, $expected) = @$pair;
		my $r = roundtrip_via_json($val);
		is($reader->($r), $expected, "$expected preserved");
	}
};

# ===== Qualified decimals =====

subtest 'amount round-trip' => sub {
	my $r = roundtrip_via_json(vof_amount(125, 1, "USD"));
	my $a = as_amount($r);
	is_deeply([$a->[0], $a->[1]], [125, 1], "amount decimal");
	is($a->[2], "USD", "amount currency");

	$r = roundtrip_via_json(vof_amount(5, 0));
	$a = as_amount($r);
	is_deeply([$a->[0], $a->[1]], [5, 0], "bare amount");
};

subtest 'tax round-trip' => sub {
	my $r = roundtrip_via_json(vof_tax(125, 1, "GST", "USD"));
	my $t = as_tax($r);
	is($t->[2], "GST", "tax_code");
	is($t->[3], "USD", "currency");

	$r = roundtrip_via_json(vof_tax(125, 1, "GST"));
	$t = as_tax($r);
	is($t->[2], "GST", "tax_code without currency");
	is($t->[3], undef, "no currency");
};

subtest 'quantity round-trip' => sub {
	my $r = roundtrip_via_json(vof_quantity(35, 1, "KGM"));
	my $q = as_quantity($r);
	is_deeply([$q->[0], $q->[1]], [35, 1], "quantity decimal");
	is($q->[2], "KGM", "unit");
};

# ===== Network types =====

subtest 'ip round-trip' => sub {
	my $orig = inet_pton(AF_INET, "192.168.1.1");
	my $r = roundtrip_via_json(vof_ip($orig));
	is(as_ip($r), $orig, "IPv4 preserved");
};

subtest 'subnet round-trip' => sub {
	my $orig = inet_pton(AF_INET, "10.0.0.0");
	my $r = roundtrip_via_json(vof_subnet($orig, 8));
	my $s = as_subnet($r);
	is($s->[0], $orig, "subnet IP preserved");
	is($s->[1], 8, "prefix length preserved");
};

subtest 'coords round-trip' => sub {
	my $r = roundtrip_via_json(vof_coords(45.5, -73.5));
	my $c = as_coords($r);
	ok(abs($c->[0] - 45.5) < 1e-6, "lat");
	ok(abs($c->[1] - (-73.5)) < 1e-6, "lon");
};

# ===== Collections =====

subtest 'list round-trip' => sub {
	my $r = roundtrip_via_json(vof_list([vof_int(1), vof_int(2), vof_int(3)]));
	is_deeply(as_list($r, \&as_int), [1, 2, 3], "list of ints");
};

subtest 'text round-trip' => sub {
	my $r = roundtrip_via_json(vof_text({ en => "Hi", fr => "Salut" }));
	my $t = as_text($r);
	is($t->{en}, "Hi", "text en");
	is($t->{fr}, "Salut", "text fr");
};

# ===== Structured =====

subtest 'record round-trip' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("order", keys => ["id"], required => []);

	my $orig = vof_record($s, {
		id    => vof_int(42),
		total => vof_decimal("99.99"),
	});
	my $encoded = VOF::JSON::encode($orig);
	my $json_str = JSON::encode_json($encoded);
	my $decoded  = JSON::decode_json($json_str);
	my $raw = VOF::JSON::decode($decoded);

	my $r = as_record($ctx, $s, $raw, sub {
		my ($f) = @_;
		return { id => as_int($f->{id}), total => as_decimal($f->{total}) };
	});
	is($r->{id}, 42, "record id");
	is_deeply($r->{total}, [9999, 2], "record total");
};

subtest 'series round-trip' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $s = $ctx->schema("order.line");

	my $orig = vof_series($s, [
		{ i => vof_int(1), qty => vof_decimal("2.5"), product => vof_string("W") },
		{ i => vof_int(2), qty => vof_decimal("3.0"), product => vof_string("G") },
	]);
	my $encoded = VOF::JSON::encode($orig, $ctx);
	my $json_str = JSON::encode_json($encoded);
	my $decoded  = JSON::decode_json($json_str);
	my $raw = VOF::JSON::decode($decoded);

	my $r = as_series($ctx, $s, $raw, sub {
		my ($f) = @_;
		return {
			i       => as_int($f->{i}),
			qty     => as_decimal($f->{qty}),
			product => as_string($f->{product}),
		};
	});
	is(scalar @$r, 2, "two rows");
	is($r->[0]{i}, 1, "row 1 i");
	is_deeply($r->[0]{qty}, [25, 1], "row 1 qty");
	is($r->[0]{product}, "W", "row 1 product");
	is($r->[1]{i}, 2, "row 2 i");
	is($r->[1]{product}, "G", "row 2 product");
};

subtest 'empty series round-trip' => sub {
	my $ctx = VOF::Context->new("test");
	my $s = $ctx->schema("thing", keys => ["id"], required => []);

	my $orig = vof_series($s, []);
	my $encoded = VOF::JSON::encode($orig);
	my $json_str = JSON::encode_json($encoded);
	my $decoded  = JSON::decode_json($json_str);
	my $raw = VOF::JSON::decode($decoded);

	my $r = as_series($ctx, $s, $raw, sub { die "should not be called" });
	is_deeply($r, [], "empty series preserved");
};

done_testing;
