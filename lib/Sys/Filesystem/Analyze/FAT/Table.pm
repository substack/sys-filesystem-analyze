package FAT::Table;
use Moose;

has fh => (is => "rw");
has fat => (is => "rw", isa => "FAT");

# linked lists of offsets representing files
has tables => (is => "rw", isa => "ArrayRef[HashRef]");

sub offsets {
    my $self = shift;
    my $fat = $self->fat;
    my $cluster = shift;
    my @entries;
    do {
        # TODO: figure out why the 6
        push @entries,
            $fat->fields->{first_data_offset}
            + ($cluster + 6) * $fat->fields->{bytes_per_cluster};
    } while $cluster = $self->tables->[0]{$cluster};
    @entries;
}

sub BUILD {
    my $self = shift;
    my $fat = $self->fat;
    my @tables;
    
    # how many bytes the fat entries have
    my ($bits) = $fat->fields->{fat_type} =~ m/FAT(\d+)/;
    
    # step through file allocation tables
    for my $fat_index (0 .. $fat->fields->{number_of_fats} - 1) {
        push @tables, {};
        
        my $ones = 2 ** $bits - 1; # 0xfff, 0xffff, or 0xfffffff
        
        my @clusters = (
            0 .. $fat->fields->{total_sectors}
                / $fat->fields->{sectors_per_cluster}
        );
        
        use POSIX qw/ceil/;
        for my $cluster (@clusters) {
            my $offset = $cluster
                * $fat->fields->{bytes_per_sector}
                * $fat->fields->{sectors_per_cluster};
            
            read $self->fh, my $buf, ceil($bits / 8);
            my $entry = (hex unpack "H*", $buf) & $ones;
            
            if ($entry == 0x0) {
                # available
                $tables[$fat_index]{$cluster} = 0x0;
            }
            elsif (0x2 <= $entry and $entry <= $ones - 16) {
                # used, next cluster in file
                $tables[$fat_index]{$cluster} = $entry;
            }
            elsif ($ones - 15 <= $entry and $entry <= $ones - 9) {
                # reserved cluster
            }
            elsif ($entry == $ones - 8) {
                # bad cluster
            }
            elsif ($entry >= $ones - 7) {
                # used, last cluster in file
                $tables[$fat_index]{$cluster} = undef;
            }
        }
    }
    
    $self->tables(\@tables);
    #for my $c (%{$tables[0]}) {
    #    my @off = $self->offsets($c);
    #    print join(" => ", @off), "\n" if @off > 1;
    #}
}

no Moose;

1;
