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
use Socket qw(AF_INET AF_INET6 inet_ntop);
use B ();
use JSON ();
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

	# JSON null → VOF_NULL
	return $VOF::null unless defined $data;

	# JSON array → VOF_RAW_TLIST (recurse)
	if (ref $data eq 'ARRAY') {
		return VOF::Value->new(VOF_RAW_TLIST,
			[map { decode($_) } @$data]);
	}

	# JSON object → VOF_RAW_TLIST of flattened [key, value, ...] pairs
	if (ref $data eq 'HASH') {
		my @pairs;
		for my $k (keys %$data) {
			push @pairs, VOF::Value->new(VOF_RAW_TSTR, $k);
			push @pairs, decode($data->{$k});
		}
		return VOF::Value->new(VOF_RAW_TLIST, \@pairs);
	}

	# JSON boolean (must precede B check — booleans have IOK set)
	if (JSON::is_bool($data)) {
		return $data ? $VOF::true : $VOF::false;
	}

	# Scalar: use B flags to recover int vs float vs string
	my $flags = B::svref_2object(\$data)->FLAGS;
	if (($flags & B::SVp_IOK) && !($flags & B::SVp_POK)) {
		return VOF::Value->new(VOF_RAW_TINT, $data);
	}
	if (($flags & B::SVp_NOK) && !($flags & B::SVp_POK)) {
		return VOF::Value->new(VOF_FLOAT, $data);
	}
	return VOF::Value->new(VOF_RAW_TSTR, $data);
}

=item C<encode( $vof_value [, $ctx ] )>

Converts a typed C<VOF::Value> into an unblessed Perl structure ready for
C<JSON::encode_json>.  The optional C<$ctx> (L<VOF::Context>) enables numeric ID
ordering of series columns; without it, columns are sorted alphabetically.

The mapping follows the VOF specification's JSON column:

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
	my ($val, $ctx) = @_;
	croak "encode: VOF::Value required" unless ref $val eq 'VOF::Value';
	my $t = $val->[0];

	# Null
	return undef if $t == VOF_NULL;

	# Bool
	return $val->[1] ? JSON::true : JSON::false if $t == VOF_BOOL;

	# Int, Uint, Timestamp, Raw_tint → number or string if outside safe range
	if ($t == VOF_INT || $t == VOF_UINT || $t == VOF_TIMESTAMP
		|| $t == VOF_RAW_TINT) {
		my $i = $val->[1];
		return ($i >= $JS_IMIN && $i <= $JS_IMAX) ? 0 + $i : "$i";
	}

	# Float
	return 0.0 + $val->[1] if $t == VOF_FLOAT;

	# String, Raw_tstr
	return "$val->[1]" if $t == VOF_STRING || $t == VOF_RAW_TSTR;

	# Data → base64url (no padding)
	return encode_base64url($val->[1]) if $t == VOF_DATA;

	# Enum → bare string
	return "$val->[2]" if $t == VOF_ENUM;

	# Variant → [name, args...]
	if ($t == VOF_VARIANT) {
		return ["$val->[2]", map { encode($_, $ctx) } @{$val->[3]}];
	}

	# Decimal → string
	if ($t == VOF_DECIMAL) {
		return VOF::decimal_to_string($val->[1], $val->[2]);
	}

	# Ratio → "n/d"
	if ($t == VOF_RATIO) {
		return VOF::ratio_to_string($val->[1], $val->[2]);
	}

	# Percent → "50%" (stored as ratio 0.5, multiply by 100 for display)
	if ($t == VOF_PERCENT) {
		return VOF::decimal_to_string($val->[1] * 100, $val->[2]) . '%';
	}

	# Date → YYYYMMDD integer
	if ($t == VOF_DATE) {
		return VOF::date_to_human($val->[1], $val->[2], $val->[3]);
	}

	# Datetime → YYYYMMDDHHMM integer
	if ($t == VOF_DATETIME) {
		return VOF::datetime_to_human(
			$val->[1], $val->[2], $val->[3], $val->[4], $val->[5]);
	}

	# Timespan → [int, int, int]
	if ($t == VOF_TIMESPAN) {
		return [0 + $val->[1], 0 + $val->[2], 0 + $val->[3]];
	}

	# Code types → string
	if ($t == VOF_CODE || $t == VOF_LANGUAGE || $t == VOF_COUNTRY
		|| $t == VOF_SUBDIVISION || $t == VOF_CURRENCY
		|| $t == VOF_TAX_CODE || $t == VOF_UNIT) {
		return "$val->[1]";
	}

	# Text → { lang: string, ... }
	if ($t == VOF_TEXT) {
		return { map { $_ => "$val->[1]{$_}" } keys %{$val->[1]} };
	}

	# Amount → "12.50" or "12.50 USD"
	if ($t == VOF_AMOUNT) {
		my $s = VOF::decimal_to_string($val->[1], $val->[2]);
		$s .= " $val->[3]" if defined $val->[3];
		return $s;
	}

	# Tax → "12.50 tax_code" or "12.50 curr tax_code"
	if ($t == VOF_TAX) {
		my $s = VOF::decimal_to_string($val->[1], $val->[2]);
		$s .= " $val->[4]" if defined $val->[4];
		$s .= " $val->[3]";
		return $s;
	}

	# Quantity → "3" or "3 KGM"
	if ($t == VOF_QUANTITY) {
		my $s = VOF::decimal_to_string($val->[1], $val->[2]);
		$s .= " $val->[3]" if defined $val->[3];
		return $s;
	}

	# IP → dotted quad or IPv6 string
	if ($t == VOF_IP) {
		return _ip_to_string($val->[1]);
	}

	# Subnet → CIDR notation
	if ($t == VOF_SUBNET) {
		return _ip_to_string($val->[1]) . '/' . $val->[2];
	}

	# Coords → [float, float]
	if ($t == VOF_COORDS) {
		return [0.0 + $val->[1], 0.0 + $val->[2]];
	}

	# Strmap → { key: value, ... }
	if ($t == VOF_STRMAP) {
		return { map { $_ => encode($val->[1]{$_}, $ctx) }
			keys %{$val->[1]} };
	}

	# Uintmap → { "key": value, ... }
	if ($t == VOF_UINTMAP) {
		return { map { $_ => encode($val->[1]{$_}, $ctx) }
			keys %{$val->[1]} };
	}

	# Record → { field: value, ... }
	if ($t == VOF_RECORD) {
		return { map { $_ => encode($val->[2]{$_}, $ctx) }
			keys %{$val->[2]} };
	}

	# List → [values...]
	if ($t == VOF_LIST) {
		return [map { encode($_, $ctx) } @{$val->[1]}];
	}

	# Ndarray → [[shape...], values...]
	if ($t == VOF_NDARRAY) {
		return [
			[map { 0 + $_ } @{$val->[1]}],
			map { encode($_, $ctx) } @{$val->[2]}
		];
	}

	# Series → [[field_names...], [row...], ...] or []
	if ($t == VOF_SERIES) {
		my $records = $val->[2];
		return [] unless @$records;
		my $fields = _series_fields($val->[1], $records, $ctx);
		my @header = map { "$_->[0]" } @$fields;
		my @out = (\@header);
		for my $rec (@$records) {
			my $row = _series_row($fields, $rec);
			push @out, [map { encode($_, $ctx) } @$row];
		}
		return \@out;
	}

	croak "VOF::JSON::encode: raw types (VOF_RAW_*) cannot be encoded";
}

=back

=cut

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _ip_to_string($bytes) - Format 4 or 16 raw bytes as IPv4/IPv6 string.
sub _ip_to_string {
	my ($bytes) = @_;
	my $len = length $bytes;
	if ($len == 4) {
		return inet_ntop(AF_INET, $bytes);
	}
	if ($len == 16) {
		return inet_ntop(AF_INET6, $bytes);
	}
	croak "VOF::JSON::encode: invalid IP address (must be 4 or 16 bytes)";
}

# _series_fields($schema, \@records, $ctx) - Collect ordered field names across
# all records in a series, sorted by numeric ID (if context available) or
# alphabetically.  Returns arrayref of [$name, $sort_key] pairs.
sub _series_fields {
	my ($schema, $records, $ctx) = @_;
	my %seen;
	for my $rec (@$records) {
		$seen{$_} = 1 for keys %$rec;
	}
	my @names = keys %seen;
	if ($ctx) {
		my $path = $schema->{path};
		return [
			sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] }
			map  { [$_, $ctx->id_by_sym($path, $_) // 1e9] } @names
		];
	}
	return [map { [$_] } sort @names];
}

# _series_row(\@field_spec, \%fields) - Extract values for the given field
# spec (from _series_fields) from a record's field hash, using VOF_NULL for
# missing fields.
sub _series_row {
	my ($field_spec, $fields) = @_;
	return [map { $fields->{$_->[0]} // $VOF::null } @$field_spec];
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
