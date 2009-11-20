#!/usr/bin/env perl
use warnings;
use strict;
use v5.10.0;

my $device = shift or die "Usage: $0 [device] {command args}";
open my $fh, "<", $device or die "$device: $!";
use Sys::Filesystem::Analyze::FAT;

my $fat = FAT->new(fh => $fh);
my $cmd = shift // "info";

if ($cmd eq "info") {
    # print out raw and computed fields separated by an empty line
    for my $key ($fat->raw, undef, $fat->computed) {
        defined $key or print "\n" and next;
        (my $disp_key = $key) =~ tr/_/ /;
        print "$disp_key: ", $fat->fields->{$key}, "\n";
    }
}
elsif ($cmd eq "full") {
    use Digest::SHA qw/sha256_hex/;
    
    my $walk; $walk = sub {
        my $file = shift;
        my $depth = shift || 0;
        for my $child ($file->list) {
            print "    " x ($depth * 2),
                $child->quote_filename,
                ($child->is_directory ? "/" : ""),
                ($child->is_deleted ? " [deleted]" : ""),
                "\n";
            print "    " x ($depth * 2 + 1), "$_->[0]: @{$_}[1..@$_-1]", "\n" for
                [ dosname => $child->quote_dosname ],
                [ size => $child->size ],
                [ cluster => $child->entry->{cluster} ],
                [ offsets => $child->offsets ],
                [ attributes => unpack "b8", $child->entry->{file_attr} ];
            if ($child->is_directory) {
                print "    " x ($depth * 2 + 1), "children:\n";
                $walk->($child, $depth + 1);
            }
            else {
                print "    " x ($depth * 2 + 1),
                    "sha 256: " => sha256_hex($child->content),
                    "\n";
            }
            print "\n";
        }
    };
    $walk->($fat->file("/"));
}
elsif ($cmd eq "list") {
    my $walk; $walk = sub {
        my $file = shift;
        my $depth = shift || 0;
        for my $child ($file->list) {
            print "    " x $depth,
                $child->quote_filename,
                ($child->is_directory ? "/" : ""),
                ($child->is_deleted ? " [deleted]" : ""),
                "\n";
            if ($child->is_directory) {
                $walk->($child, $depth + 1);
            }
        }
    };
    $walk->($fat->file("/"));
}
elsif ($cmd eq "extract") {
    my $filename = shift;
    print $_->() for $fat->file($filename)->contents;
}
else {
    print "Unknown command. Available: info, list, full, extract\n";
}
