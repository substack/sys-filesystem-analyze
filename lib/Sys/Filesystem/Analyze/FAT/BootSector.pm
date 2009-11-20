package FAT::BootSector;
use Moose;
use FAT::Unpack;

sub BUILD {
    my $self = shift;
    defined $self->fh and $self->populate;
}

has fh => (is => "rw");
has fat => (is => "rw", isa => "FAT");

sub format {
    # boot sector fields
    jump_instruction => {
        size => 3,
        format => sub { "0x" . unpack "H*", shift }
    },
    oem_name => {
        size => 8,
        format => sub { join "", '"', shift =~ m/([^\x00]+)/, '"' },
    },
    bytes_per_sector => 2,
    sectors_per_cluster => 1,
    number_of_reserved_sectors => 2,
    number_of_fats => 1,
    number_of_root_entries => 2, # 0 for fat32
    total_sectors_small => 2,
    media => 1,
    sectors_per_fat => 2,
    sectors_per_track => 2,
    number_of_heads => 2,
    hidden_sectors => 4,
    total_sectors_big => 4,
    # extended bios parameter block used by fat12 and fat16
    physical_drive_number => 1,
    # extended structure used by fat32 (disabled)
    #sectors_per_fat_big => 4,
    #fat_flags => 2,
    #version => 2,
    #cluster_number_of_root_directory_start => 4,
    #fs_info_sector => 2,
    #copy_of_boot_sector => 2,
    #reserved => { size => 12, format => sub { "..." } }, # fat32
    reserved => 1, # fat16, fat12
    extended_boot_signature => 1,
    serial_number => 4,
    volume_label => { size => 11, format => sub { qq/"@{[shift]}"/ } },
    fat_type => { size => 8, format => sub { shift } },
    boot_code => {
        size => 448, # 420
        format => sub { "..." }
    },
    boot_sector_signature => {
        size => 2,
        format => sub { map { "0x" . unpack "H*", $_ } split //, shift },
    },
}

has unpacker => (
    is => "rw",
    isa => "FAT::Unpack"
);

sub raw { shift->unpacker->raw }
sub computed { shift->unpacker->computed }
sub fields { shift->unpacker->fields }

sub populate {
    my $self = shift;
    $self->unpacker(FAT::Unpack->new(
        fh => $self->fh,
        format => [ $self->format ],
        compute => [ $self->compute ],
        default_format => sub { hex reverse unpack "h*", shift },
    ));
}

sub compute {
    # number of bytes per cluster
    bytes_per_cluster => sub {
        my $self = shift;
        $self->fields->{bytes_per_sector}
            *
        $self->fields->{sectors_per_cluster};
    },    
    # total number of sectors
    total_sectors => sub {
        my $self = shift;
        $self->fields->{total_sectors_small}
            ||
        $self->fields->{total_sectors_big};
    },
    # offset of first data sector in sectors
    first_data_sector => sub {
        my $self = shift;
        my $s = $self->fields->{number_of_reserved_sectors}
        + $self->fields->{number_of_fats} * $self->fields->{sectors_per_fat};
    },    
    # offset of first data sector in bytes
    first_data_offset => sub {
        my $self = shift;
        $self->fields->{first_data_sector} * $self->fields->{bytes_per_sector};
    },
}

no Moose;

1;
