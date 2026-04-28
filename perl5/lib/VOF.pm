package VOF;

=head1 NAME

VOF - Vanilla Object Framework

=head1 SYNOPSIS

	use VOF qw(:constructors :readers :constants);

	# Construct typed values
	my $price = vof_amount(1250, 2, "USD");    # $12.50 USD
	my $date  = vof_date(2025, 12, 31);
	my $items = vof_list([vof_string("foo"), vof_int(42)]);
	my $dec   = vof_decimal("12.50");          # from string
	my $dec2  = vof_decimal(1250, 2);          # from components

	# Read (interpret) raw decoded values
	my $d = as_decimal($raw_value);    # [$sig, $places] or undef
	my $i = as_int($raw_value);        # integer or undef

	# Schema-driven reading
	my $ctx = VOF::Context->new("com.example");
	$ctx->load("path/to/symbols.vof");
	my $schema = $ctx->schema("order");
	my $order = as_record($ctx, $schema, $raw, sub {
		my ($fields) = @_;
		# $fields is a hashref of field_name => raw VOF value
		return { id => as_int($fields->{id}), ... };
	});

	# Combine with VOF::JSON for wire encoding/decoding
	use VOF::JSON;
	my $json_ready = VOF::JSON::encode($price);
	my $raw        = VOF::JSON::decode($json_structure);

=head1 DESCRIPTION

VOF is a schema-driven type system and serialization framework.  This module
provides:

=over 4

=item * B<Type constants> — integer tags identifying each VOF type.

=item * B<Value wrappers> — blessed arrayrefs (C<VOF::Value>) pairing a type tag
with its payload.

=item *

B<Constructor functions> (C<vof_*>) — build typed VOF values with validation.

=item * B<Reader functions> (C<as_*>) — interpret raw decoded values (from JSON,
CBOR, etc.) into native Perl data, returning C<undef> on type mismatch.

=item * B<Helper functions> — utilities for decimal, ratio, date and datetime
conversions.

=item * B<VOF::Context> — loads VOF symbol table files and provides schemas for
record types, variants and enums.

=back

Constructors C<croak> on invalid input.  Readers silently return C<undef> when a
value cannot be interpreted as the requested type.

=cut

use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use Exporter qw(import);

our $VERSION = '0.01';

# ---------------------------------------------------------------------------
# Type tag constants
# ---------------------------------------------------------------------------
# Generated at compile time as inlineable constants.  The specific integer
# values are an implementation detail and must not be relied upon across
# releases.

BEGIN {
	require constant;
	my $i = 0;
	for my $name (qw(
		VOF_NULL VOF_BOOL VOF_INT VOF_UINT VOF_FLOAT VOF_STRING VOF_DATA
		VOF_ENUM VOF_VARIANT
		VOF_DECIMAL VOF_RATIO VOF_PERCENT
		VOF_TIMESTAMP VOF_DATE VOF_DATETIME VOF_TIMESPAN
		VOF_CODE VOF_LANGUAGE VOF_COUNTRY VOF_SUBDIVISION
		VOF_CURRENCY VOF_TAX_CODE VOF_UNIT
		VOF_TEXT
		VOF_AMOUNT VOF_TAX VOF_QUANTITY
		VOF_IP VOF_SUBNET VOF_COORDS
		VOF_STRMAP VOF_UINTMAP VOF_LIST VOF_NDARRAY
		VOF_RECORD VOF_SERIES
		VOF_RAW_TINT VOF_RAW_TSTR VOF_RAW_TLIST
	)) {
		constant->import({ $name => $i++ });
	}
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

my @CONSTANTS = qw(
	VOF_NULL VOF_BOOL VOF_INT VOF_UINT VOF_FLOAT VOF_STRING VOF_DATA
	VOF_ENUM VOF_VARIANT
	VOF_DECIMAL VOF_RATIO VOF_PERCENT
	VOF_TIMESTAMP VOF_DATE VOF_DATETIME VOF_TIMESPAN
	VOF_CODE VOF_LANGUAGE VOF_COUNTRY VOF_SUBDIVISION
	VOF_CURRENCY VOF_TAX_CODE VOF_UNIT
	VOF_TEXT
	VOF_AMOUNT VOF_TAX VOF_QUANTITY
	VOF_IP VOF_SUBNET VOF_COORDS
	VOF_STRMAP VOF_UINTMAP VOF_LIST VOF_NDARRAY
	VOF_RECORD VOF_SERIES
	VOF_RAW_TINT VOF_RAW_TSTR VOF_RAW_TLIST
	$null $true $false
);

my @CONSTRUCTORS = qw(
	vof_null vof_bool vof_int vof_uint vof_float vof_string vof_data
	vof_decimal vof_ratio vof_percent
	vof_timestamp vof_date vof_datetime vof_timespan
	vof_code vof_language vof_country vof_subdivision
	vof_currency vof_tax_code vof_unit
	vof_text
	vof_amount vof_tax vof_quantity
	vof_ip vof_subnet vof_coords
	vof_strmap vof_uintmap vof_list vof_ndarray
	vof_enum vof_variant vof_record vof_series
);

my @READERS = qw(
	as_bool as_int as_uint as_float as_string
	as_code as_language as_country as_subdivision
	as_currency as_tax_code as_unit
	as_data
	as_decimal as_ratio as_percent
	as_timestamp as_date as_datetime as_timespan
	as_amount as_tax as_quantity
	as_text
	as_coords as_ip as_subnet
	as_strmap as_uintmap as_list as_ndarray
	as_variant as_record as_series
);

my @HELPERS = qw(
	decimal_of_string decimal_to_string decimal_optimize
	ratio_of_string ratio_to_string
	date_of_human date_to_human
	datetime_of_human datetime_to_human
);

our @EXPORT_OK = (@CONSTANTS, @CONSTRUCTORS, @READERS, @HELPERS);
our %EXPORT_TAGS = (
	constants    => \@CONSTANTS,
	constructors => \@CONSTRUCTORS,
	readers      => \@READERS,
	helpers      => \@HELPERS,
	all          => \@EXPORT_OK,
);

# ###########################################################################
# VOF::Value — blessed value wrapper
# ###########################################################################

=head1 VOF::Value

All VOF values are blessed arrayrefs of the form:

	bless [$type_tag, @payload], 'VOF::Value'

The type tag at index 0 is one of the C<VOF_*> constants.  Payload slots
vary by type:

	Type Tag        Payload: [TAG, ...]
	--------        -------------------
	VOF_NULL        [tag]
	VOF_BOOL        [tag, $bool]             0 or 1
	VOF_INT         [tag, $value]            signed integer
	VOF_UINT        [tag, $value]            unsigned integer
	VOF_FLOAT       [tag, $value]            floating point number
	VOF_STRING      [tag, $string]
	VOF_DATA        [tag, $bytes]            binary string
	VOF_ENUM        [tag, $schema, $name]
	VOF_VARIANT     [tag, $schema, $name, \@args]
	VOF_DECIMAL     [tag, $significand, $places]
	VOF_RATIO       [tag, $numerator, $denominator]
	VOF_PERCENT     [tag, $significand, $places]  in ratio form (0.5 = 50%)
	VOF_TIMESTAMP   [tag, $epoch]            UNIX epoch seconds
	VOF_DATE        [tag, $y, $m, $d]
	VOF_DATETIME    [tag, $y, $m, $d, $hh, $mm]
	VOF_TIMESPAN    [tag, $half_months, $days, $seconds]
	VOF_CODE        [tag, $string]
	VOF_LANGUAGE    [tag, $string]           IETF BCP-47
	VOF_COUNTRY     [tag, $string]           ISO 3166-1 alpha-2
	VOF_SUBDIVISION [tag, $string]           ISO 3166-2
	VOF_CURRENCY    [tag, $string]           ISO 4217 alpha-3
	VOF_TAX_CODE    [tag, $string]
	VOF_UNIT        [tag, $string]           UN/CEFACT Rec. 20
	VOF_TEXT        [tag, \%lang_map]        { lang_code => string, ... }
	VOF_AMOUNT      [tag, $sig, $places, $currency]    $currency may be undef
	VOF_TAX         [tag, $sig, $places, $tax_code, $currency]  $curr undef ok
	VOF_QUANTITY    [tag, $sig, $places, $unit]        $unit may be undef
	VOF_IP          [tag, $bytes]            4 or 16 raw bytes
	VOF_SUBNET      [tag, $bytes, $prefix_len]
	VOF_COORDS      [tag, $lat, $lon]       WGS84 floats
	VOF_STRMAP      [tag, \%map]             { string => VOF::Value, ... }
	VOF_UINTMAP     [tag, \%map]             { uint   => VOF::Value, ... }
	VOF_LIST        [tag, \@items]           [ VOF::Value, ... ]
	VOF_NDARRAY     [tag, \@shape, \@values]
	VOF_RECORD      [tag, $schema, \%fields] { name => VOF::Value, ... }
	VOF_SERIES      [tag, $schema, \@records] [ \%fields, ... ]
	VOF_RAW_TINT    [tag, $int]              raw JSON integer
	VOF_RAW_TSTR    [tag, $string]           raw JSON string
	VOF_RAW_TLIST   [tag, \@items]           raw JSON array

Callers should use B<constructor functions> to build values and B<reader
functions> to interpret them.  Direct access to payload slots is possible
but discouraged.

=head2 Singleton Constants

Three pre-built immutable instances are available as package variables (and
exported via the C<:constants> tag):

	$VOF::null    # VOF_NULL
	$VOF::true    # VOF_BOOL 1
	$VOF::false   # VOF_BOOL 0

C<vof_null()> and C<vof_bool()> return these cached instances.

=head2 C<< VOF::Value->new($tag, @payload) >>

Low-level constructor; prefer the exported C<vof_*> functions instead.

=cut

package VOF::Value {
	sub new {
		my ($class, @args) = @_;
		return bless \@args, $class;
	}

	sub type { return $_[0][0] }
}

# ###########################################################################
# VOF::Schema — internal record schema descriptor (returned by Context)
# ###########################################################################

package VOF::Schema {
	sub new {
		my ($class, $path, %opts) = @_;
		return bless {
			path     => $path,
			keys     => $opts{keys}     || [],
			required => $opts{required} || [],
		}, $class;
	}

	sub is_reference {
		my ($self, $fields) = @_;
		my %allowed = map { $_ => 1 } @{$self->{keys}}, @{$self->{required}};
		return !grep { !$allowed{$_} } keys %$fields;
	}
}

# ###########################################################################
# VOF::Context — symbol table and schema management
# ###########################################################################

=head1 VOF::Context

Manages VOF symbol table namespaces and provides schemas for record types,
variants and enums.

=head2 C<< VOF::Context->new($root) >>

Creates a new context with the given root namespace.

	my $ctx = VOF::Context->new("com.example");

=head2 C<< $ctx->load($file_path) >>

Parses a VOF symbol table file and registers all namespaces and their symbols.
Returns C<$ctx> for chaining.  Croaks on I/O errors or malformed input.

	$ctx->load("path/to/symbols.vof");

The file format is described in the VOF specification.  Lines starting with
C<#> are comments; lines starting with a TAB are symbol definitions in the
current namespace; other lines are namespace declarations.  Symbol lines may
carry whitespace-delimited qualifiers (C<key>, C<req>); unknown qualifiers are
silently ignored.

=head2 C<< $ctx->schema($path, %opts) >>

Returns a schema object for the given relative namespace path (without the root
prefix), used by reader functions such as C<as_record>, C<as_variant> and
C<as_series>.  The root namespace is automatically prepended.  Four modes:

=over 4

=item B<Path loaded, no hints> — returns schema from file.  Typical client use.

=item B<Path loaded, hints provided> — validates that C<keys> and C<required>
match the file, croaks on mismatch.  Safety net for servers.

=item B<Path not loaded, hints provided> — returns schema from hints alone.
Useful for tests.

=item B<Path not loaded, no hints> — croaks.

=back

	# From loaded symbol table
	my $schema = $ctx->schema("order");         # looks up "com.example.order"

	# With validation hints (server-side safety net)
	my $schema = $ctx->schema("order",
		keys     => ["id"],
		required => ["mtime"],
	);

	# Standalone for tests
	my $ctx = VOF::Context->new("test");
	my $schema = $ctx->schema("thing",          # looks up "test.thing"
		keys     => ["id"],
		required => [],
	);

Options:

=over 4

=item C<keys>

Arrayref of primary key field names.

=item C<required>

Arrayref of required (non-key) field names — fields that appear in references
alongside keys.

=back

The full namespace path (C<"$root.$relative_path">) is stored in the returned
schema object.

=cut

package VOF::Context {
	use Carp qw(croak);

	sub new {
		my ($class, $root) = @_;
		return bless { root => $root, namespaces => {} }, $class;
	}

	sub load {
		my ($self, $file_path) = @_;
		open my $fh, '<', $file_path
			or croak "VOF::Context: cannot open '$file_path': $!";
		my $root_prefix = "$self->{root}.";
		my $current_ns;
		while (my $line = <$fh>) {
			$line =~ s/[\r\n]+\z//;
			next if $line eq '' || $line =~ /^#/;
			if ($line =~ /^\t(.+)/) {
				next unless defined $current_ns;
				my ($symbol, @quals) = split /\s+/, $1;
				my %flags = map { $_ => 1 } @quals;
				my $ns = ($self->{namespaces}{$current_ns} ||= {
					symbols  => [],
					keys     => [],
					required => [],
				});
				push @{$ns->{symbols}}, $symbol;
				if ($flags{key}) {
					push @{$ns->{keys}}, $symbol;
				}
				elsif ($flags{req}) {
					push @{$ns->{required}}, $symbol;
				}
			}
			else {
				if (index($line, $root_prefix) == 0) {
					$current_ns = $line;
				}
				else {
					Carp::carp(
						"VOF::Context: skipping namespace '$line'"
						. " outside root '$self->{root}' in '$file_path'"
					);
					$current_ns = undef;
				}
			}
		}
		close $fh;
		return $self;
	}

	sub schema {
		my ($self, $rel_path, %opts) = @_;
		my $path       = "$self->{root}.$rel_path";
		my $ns         = $self->{namespaces}{$path};
		my $hint_keys  = $opts{keys};
		my $hint_req   = $opts{required};
		my $have_hints = defined $hint_keys || defined $hint_req;

		if ($ns && $have_hints) {
			my $fk = join("\0", sort @{$ns->{keys}});
			my $hk = join("\0", sort @{$hint_keys || []});
			croak "VOF::Context: keys mismatch for '$path'" if $fk ne $hk;
			my $fr = join("\0", sort @{$ns->{required}});
			my $hr = join("\0", sort @{$hint_req || []});
			croak "VOF::Context: required mismatch for '$path'" if $fr ne $hr;
		}
		elsif (!$ns && !$have_hints) {
			croak "VOF::Context: unknown namespace '$path'";
		}

		return VOF::Schema->new($path,
			keys     => ($ns ? $ns->{keys}     : ($hint_keys || [])),
			required => ($ns ? $ns->{required} : ($hint_req  || [])),
		);
	}
}

# ###########################################################################
# Back to main package
# ###########################################################################

package VOF;

# ---------------------------------------------------------------------------
# Singleton constants — reusable immutable values
# ---------------------------------------------------------------------------
# Accessible as $VOF::null, $VOF::true, $VOF::false (or imported via
# :constants).  vof_null() and vof_bool() return these cached instances.

our $null  = VOF::Value->new(VOF_NULL);
our $true  = VOF::Value->new(VOF_BOOL, 1);
our $false = VOF::Value->new(VOF_BOOL, 0);

# Internal: croak unless $v is a VOF::Value
sub _check_value {
	my ($label, $v) = @_;
	croak "$label: values must be VOF::Value instances"
		unless ref $v eq 'VOF::Value';
}

# ###########################################################################
# Helper functions
# ###########################################################################

=head1 HELPER FUNCTIONS

Utility functions for working with VOF's compact representations of decimals,
ratios, dates and datetimes.  Exported via the C<:helpers> tag.

=head2 Decimal Helpers

VOF decimals are pairs C<($significand, $places)> where the real value is
C<$significand / 10**$places>.  For example, C<(1250, 2)> represents C<12.50>.
Decimal places must be in the range 0..9.

=over 4

=item C<decimal_of_string( $str )>

=item C<decimal_of_string( $str, $shift )>

Parses a decimal string such as C<"12.50"> and returns C<[$significand,
$places]> or C<undef> on failure.  Leading zeros and trailing decimal zeros are
normalized.  Non-numeric characters other than C<'-'> and C<'.'> are silently
ignored, so strings like C<"1,234.56"> and C<"50%"> are accepted.

The optional C<$shift> (default 0) adds extra decimal places to the result,
effectively dividing the parsed value by C<10 ** $shift>.  This is used
internally by the percent reader (C<$shift = 2> divides by 100) and may be
useful for any fixed-point representation that needs rescaling on parse.

=cut

sub decimal_of_string {
	my ($str, $shift) = @_;
	return undef unless defined $str;
	$shift //= 0;

	my $buf        = '';
	my $int_chars  = -1;
	my $last_nz    = 0;

	for my $c (split //, $str) {
		if ($c eq '-' || $c eq '0') {
			$buf .= $c;
		}
		elsif ($c ge '1' && $c le '9') {
			$buf .= $c;
			$last_nz = length $buf;
		}
		elsif ($c eq '.') {
			$int_chars = length $buf;
			$last_nz   = length $buf;
		}
		# else: skip (lenient)
	}

	if ($int_chars >= 0) {
		$buf = substr($buf, 0, $last_nz);
	}
	else {
		$int_chars = length $buf;
	}

	return undef unless length $buf && $buf =~ /^-?\d+\z/;
	my $i      = 0 + $buf;
	my $places = length($buf) - $int_chars + $shift;
	my ($sig, $dec) = decimal_optimize($i, $places);
	return [$sig, $dec];
}

=item C<decimal_to_string( $significand, $places )>

Returns the canonical string representation (no trailing zeros, no leading zeros
except a single C<"0"> before the decimal point).

=cut

sub decimal_to_string {
	my ($sig, $places) = @_;
	croak "decimal_to_string: places must be 0..9" if $places < 0 || $places > 9;
	return "$sig" if $places == 0;

	my $scale = 10 ** $places;
	my $i     = int($sig / $scale);
	my $f     = abs($sig % $scale);

	return "$i" if $f == 0;

	my $prefix = ($sig < 0 && $i == 0) ? '-0' : "$i";
	my $s = sprintf('%s.%0*d', $prefix, $places, $f);
	$s =~ s/0+\z//;
	return $s;
}

=item C<decimal_optimize( $significand, $places )>

Strips trailing decimal zeros, returning C<($sig, $places)>.  For example,
C<(1250, 3)> becomes C<(125, 2)>.

=cut

sub decimal_optimize {
	my ($sig, $places) = @_;
	while ($places > 0 && $sig % 10 == 0) {
		$sig = int($sig / 10);
		$places--;
	}
	return ($sig, $places);
}

=back

=head2 Ratio Helpers

VOF ratios are pairs C<($numerator, $denominator)>.

=over 4

=item C<ratio_of_string( $str )>

Parses C<"3/4"> into C<[3, 4]> or returns C<undef>.  The denominator must be
positive.

=cut

sub ratio_of_string {
	my ($str) = @_;
	return undef unless defined $str && $str =~ m{^(-?\d+)/(\d+)\z};
	my ($n, $d) = (0 + $1, 0 + $2);
	return undef unless $d > 0;
	return [$n, $d];
}

=item C<ratio_to_string( $numerator, $denominator )>

Returns the string C<"$n/$d">.

=cut

sub ratio_to_string {
	my ($n, $d) = @_;
	return "$n/$d";
}

=back

=head2 Date Helpers

Dates are C<($year, $month, $day)> tuples.

=over 4

=item C<date_of_human( $n )>

Parses a C<YYYYMMDD> integer (e.g. C<20251231>) and returns C<[$y, $m, $d]> or
C<undef> if the components are out of range.

=cut

sub date_of_human {
	my ($n) = @_;
	return undef unless defined $n;
	my $y = int($n / 10000);
	my $m = int($n % 10000 / 100);
	my $d = $n % 100;
	return undef unless $y >= 1000 && $y <= 9999
		&& $m >= 1 && $m <= 12
		&& $d >= 1 && $d <= 31;
	return [$y, $m, $d];
}

=item C<date_to_human( $y, $m, $d )>

Returns the C<YYYYMMDD> integer C<$y*10000 + $m*100 + $d>.

=cut

sub date_to_human {
	my ($y, $m, $d) = @_;
	return $y * 10000 + $m * 100 + $d;
}

=back

=head2 Datetime Helpers

Datetimes are C<($year, $month, $day, $hour, $minute)> tuples.

=over 4

=item C<datetime_of_human( $n )>

Parses a C<YYYYMMDDHHMM> integer (e.g. C<202512312359>) and returns
C<[$y, $m, $d, $hh, $mm]> or C<undef> if the components are out of range.

=cut

sub datetime_of_human {
	my ($n) = @_;
	return undef unless defined $n;
	my $y  = int($n / 100_000_000);
	my $m  = int($n / 1_000_000) % 100;
	my $d  = int($n / 10_000) % 100;
	my $hh = int($n / 100) % 100;
	my $mm = $n % 100;
	return undef unless $y >= 1000 && $y <= 9999
		&& $m >= 1  && $m <= 12
		&& $d >= 1  && $d <= 31
		&& $hh <= 23
		&& $mm <= 59;
	return [$y, $m, $d, $hh, $mm];
}

=item C<datetime_to_human( $y, $m, $d, $hh, $mm )>

Returns the C<YYYYMMDDHHMM> integer.

=cut

sub datetime_to_human {
	my ($y, $m, $d, $hh, $mm) = @_;
	return $y * 100_000_000 + $m * 1_000_000 + $d * 10_000 + $hh * 100 + $mm;
}

=back

# ###########################################################################
# Constructor functions
# ###########################################################################

=head1 CONSTRUCTOR FUNCTIONS

Exported via the C<:constructors> tag.  Each returns a blessed C<VOF::Value>.
Invalid arguments cause a C<croak>.

=head2 Scalar Constructors

=over 4

=item C<vof_null()>

Returns a C<VOF_NULL> value.

=cut

sub vof_null {
	return $null;
}

=item C<vof_bool( $value )>

Returns a C<VOF_BOOL> value.  C<$value> is normalized to C<0> or C<1>.

=cut

sub vof_bool {
	my ($val) = @_;
	return $val ? $true : $false;
}

=item C<vof_int( $value )>

Returns a C<VOF_INT> (signed integer) value.

=cut

sub vof_int {
	my ($val) = @_;
	croak "vof_int: value required" unless defined $val;
	return VOF::Value->new(VOF_INT, int($val));
}

=item C<vof_uint( $value )>

Returns a C<VOF_UINT> (unsigned integer) value.  Croaks if C<$value> is
negative.

=cut

sub vof_uint {
	my ($val) = @_;
	croak "vof_uint: value required" unless defined $val;
	my $i = int($val);
	croak "vof_uint: value must be non-negative" if $i < 0;
	return VOF::Value->new(VOF_UINT, $i);
}

=item C<vof_float( $value )>

Returns a C<VOF_FLOAT> value.

=cut

sub vof_float {
	my ($val) = @_;
	croak "vof_float: value required" unless defined $val;
	return VOF::Value->new(VOF_FLOAT, 0 + $val);
}

=item C<vof_string( $value )>

Returns a C<VOF_STRING> value.

=cut

sub vof_string {
	my ($val) = @_;
	croak "vof_string: value required" unless defined $val;
	return VOF::Value->new(VOF_STRING, "$val");
}

=item C<vof_data( $bytes )>

Returns a C<VOF_DATA> value containing raw bytes.

=cut

sub vof_data {
	my ($bytes) = @_;
	croak "vof_data: value required" unless defined $bytes;
	return VOF::Value->new(VOF_DATA, $bytes);
}

=back

=head2 Numeric Constructors

=over 4

=item C<vof_decimal( $string )>

=item C<vof_decimal( $significand, $places )>

Returns a C<VOF_DECIMAL> value.  Accepts either a string like C<"12.50"> or
explicit components.  Decimal places must be in the range 0..9.

=cut

sub vof_decimal {
	my @args = @_;
	if (@args == 1) {
		my $d = decimal_of_string($args[0]);
		croak "vof_decimal: invalid decimal string" unless defined $d;
		return VOF::Value->new(VOF_DECIMAL, $d->[0], $d->[1]);
	}
	croak "vof_decimal: expected 1 or 2 arguments" unless @args == 2;
	my ($sig, $places) = @args;
	croak "vof_decimal: places must be 0..9" if $places < 0 || $places > 9;
	($sig, $places) = decimal_optimize(int($sig), int($places));
	return VOF::Value->new(VOF_DECIMAL, $sig, $places);
}

=item C<vof_ratio( $numerator, $denominator )>

Returns a C<VOF_RATIO> value.  Croaks if denominator is not positive.

=cut

sub vof_ratio {
	my ($n, $d) = @_;
	croak "vof_ratio: arguments required" unless defined $n && defined $d;
	$d = int($d);
	croak "vof_ratio: denominator must be positive" unless $d > 0;
	return VOF::Value->new(VOF_RATIO, int($n), $d);
}

=item C<vof_percent( $string )>

=item C<vof_percent( $significand, $places )>

Returns a C<VOF_PERCENT> value stored in ratio form: C<(5, 1)> represents 50%.
From a string, C<"50%"> is parsed and divided by 100.

=cut

sub vof_percent {
	my @args = @_;
	if (@args == 1) {
		my $s = $args[0];
		croak "vof_percent: value required" unless defined $s;
		my $d = decimal_of_string($s, 2);
		croak "vof_percent: invalid percent string" unless defined $d;
		return VOF::Value->new(VOF_PERCENT, $d->[0], $d->[1]);
	}
	croak "vof_percent: expected 1 or 2 arguments" unless @args == 2;
	my ($sig, $places) = @args;
	croak "vof_percent: places must be 0..9" if $places < 0 || $places > 9;
	($sig, $places) = decimal_optimize(int($sig), int($places));
	return VOF::Value->new(VOF_PERCENT, $sig, $places);
}

=back

=head2 Temporal Constructors

=over 4

=item C<vof_timestamp( $epoch )>

Returns a C<VOF_TIMESTAMP> value (UNIX epoch seconds, signed).

=cut

sub vof_timestamp {
	my ($epoch) = @_;
	croak "vof_timestamp: value required" unless defined $epoch;
	return VOF::Value->new(VOF_TIMESTAMP, int($epoch));
}

=item C<vof_date( $year, $month, $day )>

Returns a C<VOF_DATE> value.  Croaks if month is not 1..12 or day is not 1..31.

=cut

sub vof_date {
	my ($y, $m, $d) = @_;
	croak "vof_date: year required" unless defined $y;
	croak "vof_date: month must be 1..12"
		unless defined $m && $m >= 1 && $m <= 12;
	croak "vof_date: day must be 1..31"
		unless defined $d && $d >= 1 && $d <= 31;
	return VOF::Value->new(VOF_DATE, int($y), int($m), int($d));
}

=item C<vof_datetime( $year, $month, $day, $hour, $minute )>

Returns a C<VOF_DATETIME> value.  Croaks if any component is out of range (month
1..12, day 1..31, hour 0..23, minute 0..59).

=cut

sub vof_datetime {
	my ($y, $m, $d, $hh, $mm) = @_;
	croak "vof_datetime: year required" unless defined $y;
	croak "vof_datetime: month must be 1..12"
		unless defined $m && $m >= 1 && $m <= 12;
	croak "vof_datetime: day must be 1..31"
		unless defined $d && $d >= 1 && $d <= 31;
	croak "vof_datetime: hour must be 0..23"
		unless defined $hh && $hh >= 0 && $hh <= 23;
	croak "vof_datetime: minute must be 0..59"
		unless defined $mm && $mm >= 0 && $mm <= 59;
	return VOF::Value->new(VOF_DATETIME, int($y), int($m), int($d), int($hh), int($mm));
}

=item C<vof_timespan( $half_months, $days, $seconds )>

Returns a C<VOF_TIMESPAN> value.  All three components are signed integers.

=cut

sub vof_timespan {
	my ($hm, $d, $s) = @_;
	croak "vof_timespan: three arguments required"
		unless defined $hm && defined $d && defined $s;
	return VOF::Value->new(VOF_TIMESPAN, int($hm), int($d), int($s));
}

=back

=head2 Code Constructors

These constructors each take a single string argument and return a typed VOF
value.  The string should follow the conventions for its type (see the VOF
specification for details).

=over 4

=item C<vof_code( $string )>

=item C<vof_language( $string )>

=item C<vof_country( $string )>

=item C<vof_subdivision( $string )>

=item C<vof_currency( $string )>

=item C<vof_tax_code( $string )>

=item C<vof_unit( $string )>

=cut

sub vof_code         { croak "vof_code: string required" unless defined $_[0]; VOF::Value->new(VOF_CODE, "$_[0]") }
sub vof_language     { croak "vof_language: string required" unless defined $_[0]; VOF::Value->new(VOF_LANGUAGE, "$_[0]") }
sub vof_country      { croak "vof_country: string required" unless defined $_[0]; VOF::Value->new(VOF_COUNTRY, "$_[0]") }
sub vof_subdivision  { croak "vof_subdivision: string required" unless defined $_[0]; VOF::Value->new(VOF_SUBDIVISION, "$_[0]") }
sub vof_currency     { croak "vof_currency: string required" unless defined $_[0]; VOF::Value->new(VOF_CURRENCY, "$_[0]") }
sub vof_tax_code     { croak "vof_tax_code: string required" unless defined $_[0]; VOF::Value->new(VOF_TAX_CODE, "$_[0]") }
sub vof_unit         { croak "vof_unit: string required" unless defined $_[0]; VOF::Value->new(VOF_UNIT, "$_[0]") }

=back

=head2 Text Constructor

=over 4

=item C<vof_text( \%lang_map )>

Returns a C<VOF_TEXT> value.  C<%lang_map> maps language codes (IETF BCP-47
strings) to text strings, e.g. C<< { en => "Hello", fr => "Bonjour" } >>.

=cut

sub vof_text {
	my ($map) = @_;
	croak "vof_text: hashref required" unless ref $map eq 'HASH';
	for my $v (values %$map) {
		croak "vof_text: values must be defined strings"
			unless defined $v && !ref $v;
	}
	return VOF::Value->new(VOF_TEXT, { %$map });
}

=back

=head2 Qualified Decimal Constructors

These combine a decimal value with an optional qualifier string (currency, unit
code or tax code).

=over 4

=item C<vof_amount( $sig, $places )>

=item C<vof_amount( $sig, $places, $currency )>

Returns a C<VOF_AMOUNT> value.  C<$currency> (ISO 4217) is optional.

=cut

sub vof_amount {
	my ($sig, $places, $currency) = @_;
	croak "vof_amount: significand and places required"
		unless defined $sig && defined $places;
	croak "vof_amount: places must be 0..9" if $places < 0 || $places > 9;
	($sig, $places) = decimal_optimize(int($sig), int($places));
	return VOF::Value->new(VOF_AMOUNT, $sig, $places, $currency);
}

=item C<vof_tax( $sig, $places, $tax_code )>

=item C<vof_tax( $sig, $places, $tax_code, $currency )>

Returns a C<VOF_TAX> value.  C<$tax_code> is required; C<$currency> is optional.

=cut

sub vof_tax {
	my ($sig, $places, $tax_code, $currency) = @_;
	croak "vof_tax: significand, places and tax_code required"
		unless defined $sig && defined $places && defined $tax_code;
	croak "vof_tax: places must be 0..9" if $places < 0 || $places > 9;
	($sig, $places) = decimal_optimize(int($sig), int($places));
	return VOF::Value->new(VOF_TAX, $sig, $places, "$tax_code", $currency);
}

=item C<vof_quantity( $sig, $places )>

=item C<vof_quantity( $sig, $places, $unit )>

Returns a C<VOF_QUANTITY> value.  C<$unit> (UN/CEFACT Rec. 20) is optional.

=cut

sub vof_quantity {
	my ($sig, $places, $unit) = @_;
	croak "vof_quantity: significand and places required"
		unless defined $sig && defined $places;
	croak "vof_quantity: places must be 0..9" if $places < 0 || $places > 9;
	($sig, $places) = decimal_optimize(int($sig), int($places));
	return VOF::Value->new(VOF_QUANTITY, $sig, $places, $unit);
}

=back

=head2 Network Constructors

=over 4

=item C<vof_ip( $bytes )>

Returns a C<VOF_IP> value.  C<$bytes> must be exactly 4 (IPv4) or 16 (IPv6) raw
bytes.

=cut

sub vof_ip {
	my ($bytes) = @_;
	croak "vof_ip: bytes required" unless defined $bytes;
	my $len = length $bytes;
	croak "vof_ip: must be 4 or 16 bytes" unless $len == 4 || $len == 16;
	return VOF::Value->new(VOF_IP, $bytes);
}

=item C<vof_subnet( $bytes, $prefix_len )>

Returns a C<VOF_SUBNET> value.  C<$bytes> is 4 or 16 raw bytes; C<$prefix_len>
is the CIDR prefix length.

=cut

sub vof_subnet {
	my ($bytes, $prefix_len) = @_;
	croak "vof_subnet: bytes and prefix_len required"
		unless defined $bytes && defined $prefix_len;
	my $len = length $bytes;
	croak "vof_subnet: must be 4 or 16 bytes" unless $len == 4 || $len == 16;
	return VOF::Value->new(VOF_SUBNET, $bytes, int($prefix_len));
}

=item C<vof_coords( $lat, $lon )>

Returns a C<VOF_COORDS> value.  C<$lat> and C<$lon> are WGS84 floats.

=cut

sub vof_coords {
	my ($lat, $lon) = @_;
	croak "vof_coords: lat and lon required"
		unless defined $lat && defined $lon;
	return VOF::Value->new(VOF_COORDS, 0 + $lat, 0 + $lon);
}

=back

=head2 Collection Constructors

=over 4

=item C<vof_strmap( \%map )>

Returns a C<VOF_STRMAP> value.  Values must be C<VOF::Value> instances.

=cut

sub vof_strmap {
	my ($map) = @_;
	croak "vof_strmap: hashref required" unless ref $map eq 'HASH';
	_check_value('vof_strmap', $_) for values %$map;
	return VOF::Value->new(VOF_STRMAP, { %$map });
}

=item C<vof_uintmap( \%map )>

Returns a C<VOF_UINTMAP> value.  Keys are non-negative integers (stored as Perl
hash keys); values must be C<VOF::Value> instances.

=cut

sub vof_uintmap {
	my ($map) = @_;
	croak "vof_uintmap: hashref required" unless ref $map eq 'HASH';
	for my $k (keys %$map) {
		croak "vof_uintmap: keys must be non-negative integers"
			unless $k =~ /^\d+\z/;
		_check_value('vof_uintmap', $map->{$k});
	}
	return VOF::Value->new(VOF_UINTMAP, { %$map });
}

=item C<vof_list( \@items )>

Returns a C<VOF_LIST> value.  Items must be C<VOF::Value> instances.

=cut

sub vof_list {
	my ($items) = @_;
	croak "vof_list: arrayref required" unless ref $items eq 'ARRAY';
	_check_value('vof_list', $_) for @$items;
	return VOF::Value->new(VOF_LIST, [ @$items ]);
}

=item C<vof_ndarray( \@shape, \@values )>

Returns a C<VOF_NDARRAY> (multi-dimensional array) value.  C<@shape> is a list
of dimension sizes; C<@values> must contain exactly their product.

=cut

sub vof_ndarray {
	my ($shape, $values) = @_;
	croak "vof_ndarray: shape arrayref required" unless ref $shape eq 'ARRAY';
	croak "vof_ndarray: values arrayref required" unless ref $values eq 'ARRAY';
	my $expected = 1;
	for my $dim (@$shape) {
		croak "vof_ndarray: dimensions must be positive integers"
			unless defined $dim && $dim > 0;
		$expected *= $dim;
	}
	croak "vof_ndarray: expected $expected values, got " . scalar(@$values)
		unless @$values == $expected;
	_check_value('vof_ndarray', $_) for @$values;
	return VOF::Value->new(VOF_NDARRAY, [ @$shape ], [ @$values ]);
}

=back

=head2 Structured Constructors

=over 4

=item C<vof_enum( $schema, $name )>

Returns a C<VOF_ENUM> value — a named member of the enumeration defined by
C<$schema>.

=cut

sub vof_enum {
	my ($schema, $name) = @_;
	croak "vof_enum: schema required" unless ref $schema eq 'VOF::Schema';
	croak "vof_enum: name required" unless defined $name;
	return VOF::Value->new(VOF_ENUM, $schema, "$name");
}

=item C<vof_variant( $schema, $name, @args )>

Returns a C<VOF_VARIANT> value — a tagged union case from the namespace defined
by C<$schema>, carrying zero or more C<VOF::Value> arguments.

=cut

sub vof_variant {
	my ($schema, $name, @args) = @_;
	croak "vof_variant: schema required" unless ref $schema eq 'VOF::Schema';
	croak "vof_variant: name required" unless defined $name;
	_check_value('vof_variant', $_) for @args;
	return VOF::Value->new(VOF_VARIANT, $schema, "$name", \@args);
}

=item C<vof_record( $schema, \%fields )>

Returns a C<VOF_RECORD> value.  C<%fields> maps field names (strings) to
C<VOF::Value> instances.

=cut

sub vof_record {
	my ($schema, $fields) = @_;
	croak "vof_record: schema required" unless ref $schema eq 'VOF::Schema';
	croak "vof_record: hashref required" unless ref $fields eq 'HASH';
	_check_value('vof_record', $_) for values %$fields;
	return VOF::Value->new(VOF_RECORD, $schema, { %$fields });
}

=item C<vof_series( $schema, \@records )>

Returns a C<VOF_SERIES> value — a compact list of records sharing the same
schema.  Each element of C<@records> is a hashref of
C<< field_name => VOF::Value >>.

=cut

sub vof_series {
	my ($schema, $records) = @_;
	croak "vof_series: schema required" unless ref $schema eq 'VOF::Schema';
	croak "vof_series: arrayref required" unless ref $records eq 'ARRAY';
	my @checked;
	for my $rec (@$records) {
		croak "vof_series: records must be hashrefs" unless ref $rec eq 'HASH';
		_check_value('vof_series', $_) for values %$rec;
		push @checked, { %$rec };
	}
	return VOF::Value->new(VOF_SERIES, $schema, \@checked);
}

=back

# ###########################################################################
# Reader functions
# ###########################################################################

=head1 READER FUNCTIONS

Exported via the C<:readers> tag.  Each accepts a raw C<VOF::Value> (often
produced by L<VOF::JSON/decode>) and attempts to interpret it as the requested
type.  Returns the extracted Perl data on success, or C<undef> on type mismatch.

Multi-valued types return an B<arrayref> on success, e.g.
C<< as_decimal($v) >> returns C<[$sig, $places]>.

=head2 Scalar Readers

=over 4

=item C<as_bool( $v )>

Returns C<0> or C<1>, applying broad truthiness rules (Null and zero are false;
non-empty strings, lists and maps are true), or C<undef>.

=cut

sub as_bool {
	my ($v) = @_;
	...
}

=item C<as_int( $v )>

Returns a signed integer, or C<undef>.

=cut

sub as_int {
	my ($v) = @_;
	...
}

=item C<as_uint( $v )>

Returns a non-negative integer, or C<undef>.

=cut

sub as_uint {
	my ($v) = @_;
	...
}

=item C<as_float( $v )>

Returns a floating-point number, or C<undef>.

=cut

sub as_float {
	my ($v) = @_;
	...
}

=item C<as_string( $v )>

Returns a string, or C<undef>.  Integers are stringified.

=cut

sub as_string {
	my ($v) = @_;
	...
}

=item C<as_data( $v )>

Returns a raw byte string, or C<undef>.

=cut

sub as_data {
	my ($v) = @_;
	...
}

=back

=head2 Code Readers

These are readers for string-typed codes.  All accept the same range of inputs
as L</as_string> and return a string or C<undef>.

=over 4

=item C<as_code( $v )>

=item C<as_language( $v )>

=item C<as_country( $v )>

=item C<as_subdivision( $v )>

=item C<as_currency( $v )>

=item C<as_tax_code( $v )>

=item C<as_unit( $v )>

=cut

sub as_code         { my ($v) = @_; ... }
sub as_language     { my ($v) = @_; ... }
sub as_country      { my ($v) = @_; ... }
sub as_subdivision  { my ($v) = @_; ... }
sub as_currency     { my ($v) = @_; ... }
sub as_tax_code     { my ($v) = @_; ... }
sub as_unit         { my ($v) = @_; ... }

=back

=head2 Numeric Readers

=over 4

=item C<as_decimal( $v )>

Returns C<[$significand, $places]> or C<undef>.  Parses from typed decimals, raw
integers (CBOR decimal-in-int encoding) and strings.

=cut

sub as_decimal {
	my ($v) = @_;
	...
}

=item C<as_ratio( $v )>

Returns C<[$numerator, $denominator]> or C<undef>.

=cut

sub as_ratio {
	my ($v) = @_;
	...
}

=item C<as_percent( $v )>

Returns C<[$significand, $places]> in ratio form (where 0.5 = 50%), or C<undef>.
Accepts strings with a trailing C<%> sign.

=cut

sub as_percent {
	my ($v) = @_;
	...
}

=back

=head2 Temporal Readers

=over 4

=item C<as_timestamp( $v )>

Returns a UNIX epoch integer, or C<undef>.

=cut

sub as_timestamp {
	my ($v) = @_;
	...
}

=item C<as_date( $v )>

Returns C<[$year, $month, $day]> or C<undef>.  Accepts C<YYYYMMDD> integers,
three-element lists, or typed date/datetime values.

=cut

sub as_date {
	my ($v) = @_;
	...
}

=item C<as_datetime( $v )>

Returns C<[$year, $month, $day, $hour, $minute]> or C<undef>.  Accepts
C<YYYYMMDDHHMM> integers, five-element lists, or typed date/datetime values
(dates are promoted to midnight).

=cut

sub as_datetime {
	my ($v) = @_;
	...
}

=item C<as_timespan( $v )>

Returns C<[$half_months, $days, $seconds]> or C<undef>.

=cut

sub as_timespan {
	my ($v) = @_;
	...
}

=back

=head2 Qualified Decimal Readers

=over 4

=item C<as_amount( $v )>

Returns C<[$sig, $places, $currency_or_undef]> or C<undef>.  Parses from typed
amounts, strings like C<"12.50 USD">, or bare decimals.

=cut

sub as_amount {
	my ($v) = @_;
	...
}

=item C<as_tax( $v )>

Returns C<[$sig, $places, $tax_code, $currency_or_undef]> or C<undef>.

=cut

sub as_tax {
	my ($v) = @_;
	...
}

=item C<as_quantity( $v )>

Returns C<[$sig, $places, $unit_or_undef]> or C<undef>.

=cut

sub as_quantity {
	my ($v) = @_;
	...
}

=back

=head2 Text Reader

=over 4

=item C<as_text( $v )>

Returns a hashref C<< { lang_code => string, ... } >> or C<undef>.

=cut

sub as_text {
	my ($v) = @_;
	...
}

=back

=head2 Network Readers

=over 4

=item C<as_ip( $v )>

Returns 4 or 16 raw bytes, or C<undef>.

=cut

sub as_ip {
	my ($v) = @_;
	...
}

=item C<as_subnet( $v )>

Returns C<[$bytes, $prefix_len]> or C<undef>.  Accepts CIDR strings.

=cut

sub as_subnet {
	my ($v) = @_;
	...
}

=item C<as_coords( $v )>

Returns C<[$lat, $lon]> or C<undef>.

=cut

sub as_coords {
	my ($v) = @_;
	...
}

=back

=head2 Collection Readers

These readers take a B<reader callback> to interpret each element.

=over 4

=item C<as_strmap( $v, \&value_reader )>

Returns a hashref C<< { string => value, ... } >> or C<undef>.  Each map value
is passed through C<\&value_reader>; if any call returns C<undef>, the whole
read fails.

=cut

sub as_strmap {
	my ($v, $reader) = @_;
	...
}

=item C<as_uintmap( $v, \&value_reader )>

Returns a hashref C<< { uint => value, ... } >> or C<undef>.

=cut

sub as_uintmap {
	my ($v, $reader) = @_;
	...
}

=item C<as_list( $v, \&item_reader )>

Returns an arrayref C<[ value, ... ]> or C<undef>.  Each list item is passed
through C<\&item_reader>.

=cut

sub as_list {
	my ($v, $reader) = @_;
	...
}

=item C<as_ndarray( $v, \&item_reader )>

Returns C<[\@shape, \@values]> or C<undef>.

=cut

sub as_ndarray {
	my ($v, $reader) = @_;
	...
}

=back

=head2 Structured Readers

These readers require a L<VOF::Context> and L<VOF::Schema>, plus a callback to
process the extracted fields.

=over 4

=item C<as_variant( $ctx, $schema, $v, \&callback )>

Calls C<< $callback->($name, \@args) >> where C<$name> is the variant case name
and C<\@args> are the (raw) payload values.  Returns whatever the callback
returns, or C<undef> if the value cannot be interpreted.

=cut

sub as_variant {
	my ($ctx, $schema, $v, $cb) = @_;
	...
}

=item C<as_record( $ctx, $schema, $v, \&callback )>

Calls C<< $callback->(\%fields) >> where C<%fields> maps field names to raw VOF
values.  Returns whatever the callback returns, or C<undef>.

=cut

sub as_record {
	my ($ctx, $schema, $v, $cb) = @_;
	...
}

=item C<as_series( $ctx, $schema, $v, \&callback )>

Interprets a series (2-D array with a header row of field names).  Calls
C<< $callback->(\%fields) >> for each row and collects results into an arrayref.
If any callback returns C<undef>, the whole read fails.

Returns C<\@results> or C<undef>.

=cut

sub as_series {
	my ($ctx, $schema, $v, $cb) = @_;
	...
}

=back

=head1 SEE ALSO

L<VOF::JSON> — JSON codec for VOF values.

The VOF specification: L<https://github.com/vphantom/vof>

=head1 AUTHOR

Stéphane Lavergne L<https://github.com/vphantom>

=head1 LICENSE

Copyright (c) 2023-2026 Stéphane Lavergne.

Distributed under the MIT (X11) License.
See L<https://opensource.org/license/mit>.

=cut

1;
