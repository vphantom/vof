use strict;
use warnings;
use Test::More;
use JSON ();
use VOF qw(:constants);
use VOF::JSON;

# Helper: JSON string → Perl → VOF decode
sub jdec { VOF::JSON::decode(JSON::decode_json($_[0])) }

# ===== Scalars =====

subtest 'null' => sub {
	my $v = jdec('null');
	is($v->[0], VOF_NULL, "null");
};

subtest 'booleans' => sub {
	my $t = jdec('true');
	is($t->[0], VOF_BOOL, "true type");
	is($t->[1], 1, "true value");

	my $f = jdec('false');
	is($f->[0], VOF_BOOL, "false type");
	is($f->[1], 0, "false value");
};

subtest 'integers' => sub {
	my $v = jdec('42');
	is($v->[0], VOF_RAW_TINT, "positive int type");
	is($v->[1], 42, "positive int value");

	$v = jdec('-7');
	is($v->[0], VOF_RAW_TINT, "negative int type");
	is($v->[1], -7, "negative int value");

	$v = jdec('0');
	is($v->[0], VOF_RAW_TINT, "zero type");
	is($v->[1], 0, "zero value");
};

subtest 'floats' => sub {
	my $v = jdec('3.14');
	is($v->[0], VOF_FLOAT, "float type");
	ok(abs($v->[1] - 3.14) < 1e-10, "float value");

	$v = jdec('0.0');
	is($v->[0], VOF_FLOAT, "zero float type");
};

subtest 'strings' => sub {
	my $v = jdec('"hello"');
	is($v->[0], VOF_RAW_TSTR, "string type");
	is($v->[1], "hello", "string value");

	$v = jdec('""');
	is($v->[0], VOF_RAW_TSTR, "empty string type");
	is($v->[1], "", "empty string value");
};

# ===== Collections =====

subtest 'arrays' => sub {
	my $v = jdec('[1, "two", null]');
	is($v->[0], VOF_RAW_TLIST, "array type");
	my $items = $v->[1];
	is(scalar @$items, 3, "three items");
	is($items->[0][0], VOF_RAW_TINT, "first is int");
	is($items->[0][1], 1, "first value");
	is($items->[1][0], VOF_RAW_TSTR, "second is string");
	is($items->[2][0], VOF_NULL, "third is null");
};

subtest 'empty array' => sub {
	my $v = jdec('[]');
	is($v->[0], VOF_RAW_TLIST, "empty array type");
	is(scalar @{$v->[1]}, 0, "zero items");
};

subtest 'objects → flattened list' => sub {
	my $v = jdec('{"a": 1, "b": "two"}');
	is($v->[0], VOF_RAW_TLIST, "object decodes as list");
	my $items = $v->[1];
	# Objects produce key-value pairs; order may vary
	is(scalar @$items, 4, "two pairs → four items");

	# Verify we can find both key-value pairs
	my %found;
	for (my $i = 0; $i < @$items; $i += 2) {
		my $k = $items->[$i][1];
		$found{$k} = $items->[$i + 1];
	}
	is($found{a}[0], VOF_RAW_TINT, "a is int");
	is($found{a}[1], 1, "a = 1");
	is($found{b}[0], VOF_RAW_TSTR, "b is string");
	is($found{b}[1], "two", "b = two");
};

subtest 'nested structures' => sub {
	my $v = jdec('{"items": [1, 2], "nested": {"x": true}}');
	is($v->[0], VOF_RAW_TLIST, "top-level object");

	# Find "items" pair
	my $items = $v->[1];
	my %found;
	for (my $i = 0; $i < @$items; $i += 2) {
		$found{$items->[$i][1]} = $items->[$i + 1];
	}
	is($found{items}[0], VOF_RAW_TLIST, "items is list");
	is(scalar @{$found{items}[1]}, 2, "items has 2 elements");
	is($found{nested}[0], VOF_RAW_TLIST, "nested is flattened object");
};

# ===== Direct Perl values =====

subtest 'decode undef' => sub {
	my $v = VOF::JSON::decode(undef);
	is($v->[0], VOF_NULL, "undef → null");
};

done_testing;
