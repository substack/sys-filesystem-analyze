package FAT;
use Moose;
use FAT::BootSector;
use FAT::Table;
use FAT::File;

sub BUILD {
    my $self = shift;
    $self->boot_sector(
        FAT::BootSector->new(
            fh => $self->fh,
            fat => $self,
        )
    );
    $self->table(
        FAT::Table->new(
            fh => $self->fh,
            fat => $self,
        )
    );
    $self;
}

has fh => (is => "rw");
has boot_sector => (is => "rw", isa => "FAT::BootSector");
has table => (is => "rw", isa => "FAT::Table");

sub raw { shift->boot_sector->raw }
sub computed { shift->boot_sector->computed }
sub bits { [ shift->fields->{fat_type} =~ m/FAT(\d+)/ ]->[0] }

sub file {
    my $self = shift;
    my $path = shift;
    FAT::File->new(
        path => $path,
        fat => $self,
    );
}

sub fields {
    my $self = shift;
    $self->boot_sector->fields;
}

no Moose;

1;
