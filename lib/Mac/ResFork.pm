package Mac::ResFork 0.001;

use strict;
use warnings;

use Encode qw/decode/;

sub new {

    my ($class, $fn) = @_;

    open my $fh, '<:raw', $fn or die "Error opening file $fn: $@";

    my $self = bless {fn=>$fn, fh=>$fh} => $class;

    $self->_parse();

    return $self;

}

sub get_offset {

    my ($self, $type, $id) = @_;

    my $res = $self->{types}->{$type}->{$id};
    return if (! defined $res);
    return $res->{offset};

}

sub get_data {

    my ($self, $type, $id) = @_;

    my $res = $self->{types}->{$type}->{$id};
    return if (! defined $res);
    $self->_goto( $res->{offset} );

    return $self->_read( $res->{length} );

}


sub _parse {

    my ($self) = @_;

    $self->_parse_header();
    $self->_parse_map();

    return $self;

}

sub get_types {

    my ($self) = @_;

    return keys %{ $self->{types} };

}

sub get_ids {

    my ($self, $type) = @_;

    return keys %{ $self->{types}->{$type} };

}

sub get_name {

    my ($self, $type, $id) = @_;

    return $self->{types}->{$type}->{$id}->{name};

}

sub _parse_type_list {

    my ($self) = @_;

    $self->{types} = {};
    my $list_offset  = $self->{off_map} + $self->{off_map_types};
    my $names_offset = $self->{off_map} + $self->{off_map_names};
    $self->_goto( $list_offset );
    my $n_types = unpack 's>', $self->_read(2);
    return if ($n_types == 0xffff); # indicates empty list
    for (0..$n_types) { # count is one greater than given value
        my ($type, $n, $offset) = unpack 'A4s>2', $self->_read(8);
        my $trackback = tell $self->{fh};
        $self->_goto( $list_offset + $offset );
        my $o = $list_offset + $offset;
        for (0..$n) { # count is one greater than given value
            my @fields = unpack 's>nCa3S>', $self->_read(12);
            my $id = $fields[0];
            my $off_name = $fields[1];
            my $attr_bits = $fields[2];
            my $off_data = unpack 'N', chr(0) . $fields[3]; # confirmed uint32
            my $trackback = tell $self->{fh};
            $self->_goto( $off_data + $self->{off_data} );
            my $l_data = unpack 'N', $self->_read(4);
            $self->_goto( $trackback );
            $off_data += $self->{off_data} + 4;
            
            #die "Format error: resourcePtr not zero!"
                #if ($fields[4] != 0);
            my $name = '';
            if ($off_name < 0xffff) {
                my $trackback = tell $self->{fh};
                $self->_goto( $names_offset + $off_name );
                my $l_name = unpack 'C', $self->_read(1);
                $name = decode( 'MacRoman' => $self->_read($l_name) );
                $self->_goto( $trackback );
            }

            $self->{types}->{$type}->{$id}->{offset}  = $off_data;
            $self->{types}->{$type}->{$id}->{length}  = $l_data;
            $self->{types}->{$type}->{$id}->{name}    = $name;
            $self->{types}->{$type}->{$id}->{bitmask} = $attr_bits;
            $self->{types}->{$type}->{$id}->{index}   = $_;

        }

        $self->_goto( $trackback );
    }

    return;

}

sub _parse_map {

    my ($self) = @_;
    $self->_goto( $self->{off_map} + 16 ); # skip 16 bytes (duplicate header)

    # Skip the next 8 bytes (could be parsed at least for validity but
    # currently not used. TODO: parse for validity
    $self->_goto( 8, 1 ); # skip 16 bytes (duplicate header)

    my @fields = unpack "s>*", $self->_read(4);
    $self->{off_map_types} = $fields[0];
    $self->{off_map_names} = $fields[1];

    $self->_parse_type_list();

     return;

}

sub _parse_header {

    my ($self) = @_;
    $self->_goto(0);
    my @fields = unpack "l>*", $self->_read(16);
    $self->{off_data} = $fields[0];
    $self->{off_map}  = $fields[1];
    $self->{len_data} = $fields[2];
    $self->{len_map}  = $fields[3];

}

sub _read {

    my ($self, $bytes) = @_;

    my $r = read($self->{fh}, my $buffer, $bytes);
    die "Failed to read correct byte count"
        if ($r != $bytes);

    return $buffer;

}

sub _goto {

    my ($self, $offset, $whence) = @_;

    $whence = $whence // 0;

    seek $self->{fh}, $offset, $whence
        or die "Seek failed: $@";

    return;

}

1;

__END__

=head1 NAME

Mac::ResFork - Parse a Macintosh resource fork file

=head1 SYNOPSIS

    use Mac::ResFork;

    my $rsrc = Mac::ResFork->new("path/to/file")

    # fill in details

=head1 ABSTRACT

This modules parses the structure of a Macintosh resource fork and provides
access to individiual data resource offsets and sizes by ID or name.

=cut

