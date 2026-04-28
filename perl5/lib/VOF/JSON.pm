package VOF::JSON;

=head1 NAME

VOF::JSON - JSON codec for VOF values

=head1 SYNOPSIS

	use VOF qw(:constructors :readers :constants);
	use VOF::JSON;
	use JSON;

	# Decoding: JSON string -> Perl structure -> raw VOF values
	my $perl = decode_json($json_text);
	my $raw  = VOF::JSON::decode($perl);
	# Now use readers to interpret the raw values
	my $amount = as_amount($raw);

	# Encoding: VOF values -> Perl structure -> JSON string
	my $price     = vof_amount(1250, 2, "USD");
	my $json_data = VOF::JSON::encode($price);
	my $json_text = encode_json($json_data);

=head1 DESCRIPTION

This module converts between typed VOF values (C<VOF::Value> instances) and
plain Perl data structures suitable for L<JSON> (or L<JSON::XS>) serialization.

B<Encoding> (C<encode>) takes a C<VOF::Value> and returns an unblessed Perl
structure (scalars, arrayrefs, hashrefs, C<JSON::true>/C<JSON::false>) ready to
be passed to C<JSON::encode_json>.

B<Decoding> (C<decode>) takes a Perl structure as returned by
C<JSON::decode_json> and wraps it in raw VOF values (C<VOF_RAW_TINT>,
C<VOF_RAW_TSTR>, C<VOF_RAW_TLIST>, etc.) that can then be interpreted by the
C<as_*> reader functions in L<VOF>.

=cut

use 5.020;
use strict;
use warnings;
use Carp qw(croak);
use MIME::Base64 qw(encode_base64url decode_base64url);
use JSON::PP ();
use VOF qw(:constants);

our $VERSION = '0.01';

# JavaScript Number.MAX_SAFE_INTEGER / MIN_SAFE_INTEGER
my $JS_IMAX =  9_007_199_254_740_991;
my $JS_IMIN = -9_007_199_254_740_991;

=head1 FUNCTIONS

=over 4

=item C<decode( $perl_structure )>

Converts a Perl data structure (as returned by C<JSON::decode_json>) into a raw
C<VOF::Value>.  The mapping is:

	JSON null       => VOF_NULL
	JSON true/false => VOF_BOOL
	JSON number     => VOF_RAW_TINT (if integer) or VOF_FLOAT
	JSON string     => VOF_RAW_TSTR
	JSON array      => VOF_RAW_TLIST (recursively decoded)
	JSON object     => VOF_RAW_TLIST (alternating keys and values)

JSON objects are flattened to C<[key, value, key, value, ...]> lists to match
the generic wire format consumed by L<VOF> readers.

Returns a C<VOF::Value>.

=cut

sub decode {
	my ($data) = @_;
	...
}

=item C<encode( $vof_value )>

Converts a typed C<VOF::Value> into an unblessed Perl structure ready for
C<JSON::encode_json>.  The mapping follows the VOF specification's JSON column:

	VOF_NULL          => undef
	VOF_BOOL          => JSON::true / JSON::false
	VOF_INT/UINT      => number, or string if outside safe integer range
	VOF_FLOAT         => number
	VOF_STRING        => string
	VOF_DATA          => base64url-encoded string (no padding)
	VOF_DECIMAL       => string (canonical decimal notation)
	VOF_RATIO         => string ("n/d")
	VOF_PERCENT       => string ("50%")
	VOF_DATE          => YYYYMMDD integer
	VOF_DATETIME      => YYYYMMDDHHMM integer
	VOF_TIMESTAMP     => integer (or string if outside safe range)
	VOF_TIMESPAN      => [int, int, int]
	VOF_ENUM          => string
	VOF_VARIANT       => [string, args...]
	VOF_CODE etc.     => string
	VOF_TEXT          => { lang: string, ... }
	VOF_AMOUNT        => string ("12.50" or "12.50 USD")
	VOF_TAX           => string ("12.50 USD GST" or "12.50 GST")
	VOF_QUANTITY      => string ("3" or "3 KGM")
	VOF_IP            => string (dotted-quad or IPv6 notation)
	VOF_SUBNET        => string (CIDR notation)
	VOF_COORDS        => [float, float]
	VOF_STRMAP        => { key: value, ... }
	VOF_UINTMAP       => { "key": value, ... }  (keys stringified)
	VOF_LIST          => [values...]
	VOF_NDARRAY       => [[shape...], values...]
	VOF_RECORD        => { field: value, ... }
	VOF_SERIES        => [[field_names...], [row...], ...] or []

Croaks on raw types (C<VOF_RAW_*>) which cannot be meaningfully encoded.

=cut

sub encode {
	my ($val) = @_;
	...
}

=back

=cut

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _ip_to_string($bytes) - Format 4 or 16 raw bytes as IPv4/IPv6 string.
sub _ip_to_string {
	my ($bytes) = @_;
	...
}

# _series_fields($schema, \@records) - Collect ordered field names across all
# records in a series.
sub _series_fields {
	my ($schema, $records) = @_;
	...
}

# _series_row(\@field_names, \%fields) - Extract values for the given field
# names from a record's field hash, using VOF_NULL for missing fields.
sub _series_row {
	my ($field_names, $fields) = @_;
	...
}

=head1 DEPENDENCIES

=over 4

=item L<JSON> (or L<JSON::XS> as a drop-in backend)

=item L<MIME::Base64> (core module)

=back

=head1 SEE ALSO

L<VOF> — Type system, constructors and readers.

The VOF specification: L<https://github.com/vphantom/vof>

=head1 AUTHOR

Stéphane Lavergne L<https://github.com/vphantom>

=head1 LICENSE

Copyright (c) 2023-2026 Stéphane Lavergne.

Distributed under the MIT (X11) License.
See L<https://opensource.org/license/mit>.

=cut

1;
