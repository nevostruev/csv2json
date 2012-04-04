#!/usr/bin/perl

use strict;
use warnings;

use JSON;
use Text::CSV;
use Getopt::Long;

{
	## try to load Tie::IxHash
	my $ordered_hash_available = eval { require Tie::IxHash };

	my $separator = ",";
	my $show_help = 0;
	GetOptions(
		"--separator|s=s" => \$separator,
		"--help|h!" => \$show_help,
	) or show_help();
	show_help() if $show_help;

	## use STDIN if file name is not specified
	my $fn = ( @ARGV ? shift @ARGV : "-" );

	my $data = read_csv($fn, $ordered_hash_available);
	print to_json(
		$data, 
		{
			'utf8' => 1, 
			'pretty' => 1,
		}
	);
}

sub read_csv {
	my ($fn, $ordered_hash_available) = @_;

	my $csv = Text::CSV->new(
		{
			'binary' => 1 
		} 
	) or die "can't create Text::CSV: ".Text::CSV->error_diag();

	open(my $fh, $fn) or die "can't read [$fn]: $!";
	binmode($fh, ":utf8");
	my ($columns, @rows);
	while ( my $row = $csv->getline( $fh ) ) {
		if (defined $columns) {
			my %r;
			if ($ordered_hash_available) {
				tie %r, "Tie::IxHash";
			}
			@r{@$columns} = @$row;
			push(@rows, \%r);
		} else {
			$columns = $row;
		}
	}

	close($fh);

	return \@rows;
}

sub show_help {
	print "Usage: $0 [--separator=?] [--help] [file]\n";
	exit(1);
}