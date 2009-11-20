package FAT::Unpack;
use Moose;

# setable attributes:
has fh => (is => "rw");

has format => (
    is => "rw",
    isa => "ArrayRef",
    default => sub { [] },
);
 
has compute => (
    is => "rw",
    isa => "ArrayRef",
    default => sub { [] },
);
 
has default_format => (
    is => "rw",
    isa => "CodeRef",
    default => sub { sub {
        my $buf = shift;
        if (length $buf < 8) {
            hex reverse unpack "h*", $buf;
        }
        else {
            #$buf =~ s/([^[:print:]])/"\\x" . ord $1/eg;
            $buf;
        }
    } }
);

# generated attributes:
has fields => (
    is => "ro",
    isa => "HashRef",
    default => sub { {} },
);
has raw_data => (is => "ro", isa => "Str");

has raw_fields => (
    is => "ro",
    isa => "ArrayRef",
    default => sub { [] },
);
sub raw { @{ shift->raw_fields } }

has computed_fields => (
    is => "ro",
    isa => "ArrayRef",
    default => sub { [] },
);
sub computed { @{ shift->computed_fields } }

sub BUILD {
    my $self = shift;
    use List::AllUtils qw/natatime/;
    $self->{raw_data} = "";
    
    # pull out raw fields
    {
        my $it = natatime 2, @{ $self->format };
        while (my ($field, $opts) = $it->()) {
            push @{$self->raw_fields}, $field;
            if (ref $opts eq "") {
                # only size is given, give default formatting
                $opts = {
                    size => $opts,
                    # endianness is super annoying to get right
                    # convert these fields to integers
                    format => $self->default_format,
                };
            }
            read $self->fh, my $buf, $opts->{size};
            $self->{raw_data} .= $buf;
            $self->fields->{$field} = join " ", $opts->{format}($buf);
        }
    }
    
    # compute field values that depend on raw fields
    {
        my $it = natatime 2, @{ $self->compute };
        while (my ($field, $sub) = $it->()) {
            push @{$self->computed_fields}, $field;
            $self->fields->{$field} = join " ", $sub->($self);
        }
    }
}

no Moose;

1;
