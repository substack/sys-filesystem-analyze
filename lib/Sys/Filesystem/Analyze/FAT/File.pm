package FAT::File;
use Moose;
use List::AllUtils qw/first min/;

has fat => (is => "rw", isa => "FAT");
has path => (is => "rw", isa => "Str");
has parents => (is => "rw", isa => "ArrayRef");
has lfn => (is => "rw", isa => "Str");

sub filename {
    my $self = shift;
    join "", $self->lfn =~ m/([^\x00\xff]+)/g
        or
    $self->dosname;
}

sub quote_filename {
    my $f = shift->filename;
    $f =~ s/([^\w.\s~-])/'\x'.(unpack "H2", $1)/eg; $f;
}

sub dosname {
    my $entry = shift->entry;
    join "",
        $entry->{dos_name},
        (length $entry->{dos_ext} ? ".$entry->{dos_ext}" : "")
}

sub quote_dosname {
    my $f = shift->dosname;
    $f =~ s/([^\w.\s~-])/'\x'.(unpack "H2", $1)/eg; $f;
}
sub size {
    my $self = shift;
    $self->is_directory
        ? 0
        : $self->entry->{file_size}
}

sub is_directory { shift->entry->{file_attr} & 0x10 }
sub is_available { shift->dosname =~ m/^\x00/; }
sub is_deleted { shift->dosname =~ m/^\xe5/; }

has entry => (
    is => "rw",
    isa => "HashRef",
);

sub offsets {
    my $self = shift;
    my $fat = $self->fat;
    
    if ($self->path eq "/" or $self->path eq "") {
        # special sequential offsets for root
        return map {
            $fat->fields->{first_data_offset}
                + $_ * $fat->fields->{bytes_per_cluster}
        } 0 .. $fat->fields->{number_of_root_entries} * 32
            / $fat->fields->{bytes_per_cluster};
    }
    else {
        $fat->table->offsets($self->entry->{cluster});
    }
}

sub contents {
    my $self = shift;
    my $fat = $self->fat;
    my $total = 0;
    
    my @blocks;
    for my $offset ($self->offsets) {
        my $size = min $fat->fields->{bytes_per_cluster}, $self->size - $total;
        $total += $size;
        push @blocks, sub {
            seek $fat->fh, $offset, 0;
            read $fat->fh, (my $buf), $size;
            $buf;
        };
    }
    @blocks;
}

sub content {
    my $self = shift;
    join "", map $_->(), $self->contents;
}

sub parent { shift->parents->[0] }

sub BUILD {
    my $self = shift;
    my $fat = $self->fat;
    
    # skip the traversal for internal construction with parents defined
    defined $self->parents and return;
    
    # seek to the root
    seek $fat->fh, $fat->fields->{first_data_offset}, 0;
    
    # start at simulated root file
    my $cursor = FAT::File->new(
        fat => $fat,
        entry => {
            # root size in bytes (<FAT32)
            file_size => $fat->fields->{number_of_root_entries} * 32,
            cluster => $fat->fields->{first_data_offset},
            dosname => "root",
            file_attr => 0x10,
        },
        path => "/",
        parents => [],
    );
    
    my @path = grep length, split m{/}, $self->path;
    for my $dir (@path) {
        $cursor = first {
            uc $_->filename eq uc $dir
                or
            uc $_->dosname eq uc $dir
        } $cursor->list
            or die qq/File not found: "$dir" in (@{[ $self->path ]})/
    }
    
    # assume the cursor's identity
    $self->entry($cursor->entry);
    $self->parents($cursor->parents);
}

sub list {
    my $self = shift;
    my $fat = $self->fat;
    
    use FAT::Unpack;
    
    my @files;
    my @offsets = $self->offsets;
    
    for my $offset (@offsets) {
        seek $fat->fh, $offset, 0;
        
        my $lfn = "";
        for (0 .. $fat->fields->{bytes_per_cluster} / 32) {
            my $file = $self->_parse_entry($lfn);
            if (ref $file eq "FAT::File") {
                $file->lfn($lfn);
                push @files, $file;
                $lfn = "";
            }
            elsif (defined $file) {
                $lfn = $file . $lfn;
            }
            else {
                $lfn = "";
            }
        }
    }
    @files;
}

sub _parse_entry {
    my $self = shift;
    my $fat = $self->fat;
    my $entry = FAT::Unpack->new(
        fh => $fat->fh,
        format => [
            dos_name => { size => 8, format => sub { shift =~ m/([^ ]+)/ } },
            dos_ext => { size => 3, format => sub { shift =~ m/([^ ]+)/ } },
            file_attr => 1,
            reserved => 1,
            ctime_fine => 1,
            ctime_hms => 2,
            ctime_date => 2,
            atime_date => 2,
            cluster_high => 2, # high 2 bytes of first cluster in fat32
            mtime_hms => 2,
            mtime_date => 2,
            cluster_low => 2, # low 2 bytes of first cluster in fat32
            file_size => 4,
        ],
        compute => [
            cluster => sub {
                my $self = shift;
                # ($fat->bits == 32 ? $self->fields->{cluster_high} << 8 : 0)
                $self->fields->{cluster_low};
            },
        ],
    );
    my $attr = $entry->fields->{file_attr};
    if ($attr == 0xf) {
        return join "", $entry->raw_data =~ m/^
            . # sequence number
            (.{10}) # name
            .{3} # attributes, reserved, checksum
            (.{12}) # name
            .. # first cluster
            (.{4}) # name
        /xs;
    }
    elsif ($attr and not $attr & 0x80) {
        return FAT::File->new(
            fat => $fat,
            entry => $entry->fields,
            path => $self->path . "/" . $entry->fields->{dos_name},
            parents => [ @{$self->parents}, $self ],
        ) if $entry->fields->{dos_name} !~ m/^ \.  \.? $/x;
    }
}

no Moose;

1;
