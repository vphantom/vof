use strict;
use warnings;
use Test::More;
use VOF qw(:constants);

# ===== Basic construction =====

subtest 'new and unknown namespace' => sub {
	my $ctx = VOF::Context->new("test");
	eval { $ctx->schema("nonexistent") };
	like($@, qr/unknown namespace/, "unknown namespace croaks");
};

# ===== Load symbol table =====

subtest 'load symbol table' => sub {
	my $ctx = VOF::Context->new("test");
	my $ret = $ctx->load("t/data/test_symbols.txt");
	is($ret, $ctx, "load returns self for chaining");
};

subtest 'load with foreign namespace warns' => sub {
	my $ctx = VOF::Context->new("test");
	my @warnings;
	local $SIG{__WARN__} = sub { push @warnings, $_[0] };
	$ctx->load("t/data/test_foreign_ns.txt");
	is(scalar @warnings, 1, "one warning about foreign namespace");
	like($warnings[0], qr/skipping namespace.*other\.foreign/,
		"warns about foreign ns");
	# Valid namespaces still loaded
	is($ctx->sym_by_id("test.valid", 0), "alpha", "valid ns loaded");
	is($ctx->sym_by_id("test.also_valid", 0), "omega", "second valid ns loaded");
	# Foreign namespace not loaded
	is($ctx->sym_by_id("other.foreign", 0), undef, "foreign ns not loaded");
};

subtest 'load bad file' => sub {
	my $ctx = VOF::Context->new("test");
	eval { $ctx->load("t/data/nonexistent.vof") };
	like($@, qr/cannot open/, "missing file croaks");
};

# ===== Symbol table contents =====

subtest 'sym_by_id and id_by_sym' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	# test.order namespace
	is($ctx->sym_by_id("test.order", 0), "id", "order field 0 → id");
	is($ctx->sym_by_id("test.order", 1), "modified_at", "order field 1");
	is($ctx->sym_by_id("test.order", 2), "customer", "order field 2");
	is($ctx->sym_by_id("test.order", 3), "lines", "order field 3");
	is($ctx->sym_by_id("test.order", 4), "total", "order field 4");
	is($ctx->sym_by_id("test.order", 99), undef, "out of range → undef");

	is($ctx->id_by_sym("test.order", "id"), 0, "id → 0");
	is($ctx->id_by_sym("test.order", "total"), 4, "total → 4");
	is($ctx->id_by_sym("test.order", "nope"), undef, "unknown symbol");

	# test.status namespace (enum-like)
	is($ctx->sym_by_id("test.status", 0), "Draft", "status 0");
	is($ctx->sym_by_id("test.status", 3), "Delivered", "status 3");

	# unknown namespace
	is($ctx->sym_by_id("test.nope", 0), undef, "unknown ns → undef");
	is($ctx->id_by_sym("test.nope", "x"), undef, "unknown ns sym → undef");
};

# ===== Schema =====

subtest 'schema from loaded file' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	my $s = $ctx->schema("order");
	isa_ok($s, "VOF::Schema");
	is($s->{path}, "test.order", "path");
	is_deeply($s->{keys}, ["id"], "keys from file");
	is_deeply($s->{required}, ["modified_at"], "required from file");
};

subtest 'schema with matching hints' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	# Matching hints should succeed
	my $s = $ctx->schema("order",
		keys     => ["id"],
		required => ["modified_at"],
	);
	is($s->{path}, "test.order", "path with matching hints");
};

subtest 'schema with mismatched hints' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	eval { $ctx->schema("order", keys => ["wrong"], required => ["modified_at"]) };
	like($@, qr/keys mismatch/, "wrong keys croaks");

	eval { $ctx->schema("order", keys => ["id"], required => ["wrong"]) };
	like($@, qr/required mismatch/, "wrong required croaks");
};

subtest 'schema standalone (hints only)' => sub {
	my $ctx = VOF::Context->new("mytest");
	my $s = $ctx->schema("widget",
		keys     => ["id"],
		required => [],
	);
	is($s->{path}, "mytest.widget", "path");
	is_deeply($s->{keys}, ["id"], "keys from hints");
};

# ===== Schema is_reference =====

subtest 'is_reference' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");
	my $s = $ctx->schema("order");

	# Only key + required fields → reference
	ok($s->is_reference({ id => 1, modified_at => 2 }), "key+required is ref");
	ok($s->is_reference({ id => 1 }), "key-only is ref");

	# Extra fields → not a reference
	ok(!$s->is_reference({ id => 1, customer => "x" }), "extra field → not ref");
	ok(!$s->is_reference({ id => 1, modified_at => 2, total => 3 }), "with total → not ref");
};

done_testing;
