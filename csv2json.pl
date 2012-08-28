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
	my $write = "json";
	my $trim_whitespaces = 0;
	my $auto_group = 0;
	GetOptions(
		"--separator|s=s" => \$separator,
		"--help|h!" => \$show_help,
		"--write=s" => \$write,
		"--trim-whitespaces!" => \$trim_whitespaces,
		"--auto-group!" => \$auto_group,
	) or show_help();
	show_help() if $show_help;

	## use STDIN if file name is not specified
	my $fn = ( @ARGV ? shift @ARGV : "-" );

	my $data = read_csv($fn, $ordered_hash_available, $separator, $trim_whitespaces);
	if ($auto_group) {
		$data = auto_group($data, $ordered_hash_available);
	}
	if ($write eq 'csv') {
		write_csv($data, $separator);
	} else {
		write_json($data);
	}
}

sub write_json {
	my ($data) = @_;

	print to_json(
		$data, 
		{
			'utf8' => 1, 
			'pretty' => 1,
		}
	);
}

sub write_csv {
    my ($data, $separator) = @_;
	
	my $csv = Text::CSV->new(
		{
			'binary' => 1,
			'sep_char' => $separator,
			'eol' => $/,
		} 
	) or die "can't create Text::CSV: ".Text::CSV->error_diag();

	if (@$data) {
		my @columns = keys %{ $data->[0] };
		$csv->print(\*STDOUT, \@columns);
		for my $row (@$data) {
			$csv->print(\*STDOUT, [ @$row{@columns} ]);
		}
	}
}

sub read_csv {
	my ($fn, $ordered_hash_available, $separator, $trim_whitespaces) = @_;

	my $csv = Text::CSV->new(
		{
			'binary' => 1,
			'sep_char' => $separator,
			'allow_whitespace' => $trim_whitespaces,
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

sub auto_group {
    my ($data, $ordered_hash_available) = @_;
	
	if (@$data) {
		my @columns = keys %{ $data->[0] };
		if (@columns == 3) {
			my ($group, $key, $value) = @columns;
			my (%all_keys, %grouped);
			if ($ordered_hash_available) {
				tie %all_keys, "Tie::IxHash";
				tie %grouped, "Tie::IxHash";
			}
			for my $row (@$data) {
				$all_keys{$row->{$key}} = 1;
				$grouped{$row->{$group}}{$row->{$key}} = $row->{$value};
			}
			my @new_data;
			for my $group_key (keys %grouped) {
				my %r;
				if ($ordered_hash_available) {
					tie %r, "Tie::IxHash";
				}
				$r{$group} = $group_key;
				for my $key (keys %all_keys) {
					$r{$key} = $grouped{$group_key}{$key};
				}
				push(@new_data, \%r);
			}
			return \@new_data;
		} else {
			die "auto-group only works with 3 columns";
		}
	}
}

sub show_help {
	print "Usage: $0 [--separator=?] [--write=json|csv] [--trim-whitespaces] [--auto-group] [--help] [file]\n";
	exit(1);
}