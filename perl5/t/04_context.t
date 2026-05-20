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

# ===== Invalid namespace/symbol characters =====

subtest 'invalid namespace characters' => sub {
	eval { VOF::Context->new("test space") };
	like($@, qr/invalid namespace/, "space in namespace croaks");

	eval { VOF::Context->new("test!name") };
	like($@, qr/invalid namespace/, "bang in namespace croaks");
};

subtest 'invalid symbol characters' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	eval { $ctx->id_by_sym("test.order", "bad name") };
	like($@, qr/invalid symbol/, "space in symbol croaks");

	eval { $ctx->id_by_sym("test.order", "bad!sym") };
	like($@, qr/invalid symbol/, "bang in symbol croaks");
};

# ===== Case and hyphen normalization =====

subtest 'case and hyphen normalization' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	is($ctx->id_by_sym("test.order", "Modified-At"), 1,
		"hyphen variant resolves");
	is($ctx->id_by_sym("test.order", "MODIFIED_AT"), 1,
		"uppercase variant resolves");
	is($ctx->id_by_sym("test.order", "ID"), 0,
		"uppercase ID resolves");
};

# ===== Alias resolution =====

subtest 'alias resolution' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	# Alias → same ID as canonical
	is($ctx->id_by_sym('test.$locale', "en"), 0, "alias 'en' → ID 0");
	is($ctx->id_by_sym('test.$locale', "en_CA"), 0, "alias 'en_CA' → ID 0");
	is($ctx->id_by_sym('test.$locale', "fr"), 1, "alias 'fr' → ID 1");

	# Canonical symbol also works
	is($ctx->id_by_sym('test.$locale', "en_US"), 0, "canonical 'en_US' → ID 0");
	is($ctx->id_by_sym('test.$locale', "fr_CA"), 1, "canonical 'fr_CA' → ID 1");

	# sym_by_id always returns canonical form
	is($ctx->sym_by_id('test.$locale', 0), "en_US", "ID 0 → canonical 'en_US'");
	is($ctx->sym_by_id('test.$locale', 1), "fr_CA", "ID 1 → canonical 'fr_CA'");

	# Currency alias
	is($ctx->id_by_sym('test.$currency', "cad"), 1, "alias 'cad' → ID 1");
	is($ctx->sym_by_id('test.$currency', 1), "CAD", "ID 1 → canonical 'CAD'");
};

# ===== canon_* methods =====

subtest 'canon methods' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	is($ctx->canon_locale("en"), "en_US", "alias → canonical");
	is($ctx->canon_locale("en_US"), "en_US", "canonical → canonical");
	is($ctx->canon_locale("unknown"), "unknown", "unknown → passthrough");

	is($ctx->canon_currency("cad"), "CAD", "currency alias → canonical");
	is($ctx->canon_currency("USD"), "USD", "currency canonical → canonical");
	is($ctx->canon_currency("GBP"), "GBP", "unknown currency → passthrough");
};

# ===== is_default_locale =====

subtest 'is_default_locale' => sub {
	my $ctx = VOF::Context->new("test");
	$ctx->load("t/data/test_symbols.txt");

	ok($ctx->is_default_locale("en_US"), "canonical default locale");
	ok($ctx->is_default_locale("en"), "alias of default locale");
	ok($ctx->is_default_locale("en_CA"), "another alias of default locale");
	ok(!$ctx->is_default_locale("fr_CA"), "non-default locale");
	ok(!$ctx->is_default_locale("fr"), "alias of non-default locale");
	ok(!$ctx->is_default_locale(""), "empty string is not default");

	# Without $locale namespace
	my $ctx2 = VOF::Context->new("nolocale");
	ok($ctx2->is_default_locale(""), "empty string is default without \$locale");
	ok(!$ctx2->is_default_locale("en"), "'en' is not default without \$locale");
};

# ===== Duplicate alias croaks =====

subtest 'duplicate alias croaks' => sub {
	my $ctx = VOF::Context->new("test");
	eval { $ctx->load("t/data/test_dup_alias.txt") };
	like($@, qr/duplicate alias/, "duplicate alias across symbols croaks");
};

done_testing;
