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
	my $join_csv = undef;
	GetOptions(
		"--separator|s=s" => \$separator,
		"--help|h!" => \$show_help,
		"--write=s" => \$write,
		"--trim-whitespaces!" => \$trim_whitespaces,
		"--auto-group!" => \$auto_group,
		"--join-csv=s" => \$join_csv,
	) or show_help();
	show_help() if $show_help;

	## use STDIN if file name is not specified
	my $fn = ( @ARGV ? shift @ARGV : "-" );

	my $data = read_csv($fn, $ordered_hash_available, $separator, $trim_whitespaces);
	if ($auto_group) {
		$data = auto_group($data, $ordered_hash_available);
	}
	if (defined $join_csv) {
		my $join_data = read_csv($join_csv, $ordered_hash_available, $separator, $trim_whitespaces);
		$data = join_data($data, $join_data, $ordered_hash_available);
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
				if (exists $grouped{$row->{$group}}{$row->{$key}})  {
					die "duplicated value at [" . $row->{$group} . "] key [" . $row->{$key} . "]";
				}
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

sub join_data {
    my ($data, $join_data, $ordered_hash_available) = @_;
	
	if (@$join_data) {
		my @join_columns = keys %{ $join_data->[0] };
		my $join_column = $join_columns[0];
		my %join;
		for my $join_row (@$join_data) {
			if (exists $join{$join_row->{$join_column}}) {
				die "duplicated value in join data [" . $join_row->{$join_column} . "] (column $join_column)";
			}
			$join{$join_row->{$join_column}} = $join_row;
		}
		if (@$data) {
			my %data_used_in_join;
			my @main_columns = keys %{ $data->[0] };
			my $main_column = $main_columns[0];
			for my $row (@$data) {
				my $row_id = $row->{$main_column};
				if (exists $join{$row_id}) {
					$data_used_in_join{$row_id} = 1;
					for my $column (@join_columns) {
						$row->{$column} = $join{$row_id}{$column};
					}
				} else {
					for my $column (@join_columns) {
						unless (exists $row->{$column}) {
							$row->{$column} = undef;
						}
					}
				}
			}
			## adding data that was not joined
			for my $row_id (keys %join) {
				unless (exists $data_used_in_join{$row_id}) {
					my %r;
					if ($ordered_hash_available) {
						tie %r, "Tie::IxHash";
					}
					for my $column (@main_columns) {
						$r{$column} = undef;
					}
					for my $column (@join_columns) {
						$r{$column} = $join{$row_id}{$column};
					}
					push(@$data, \%r);
				}
			}
			return $data;
		} else {
			return $join_data;
		}
	} else {
		return $data;
	}
}

sub show_help {
	print "Usage: $0 [--separator=?] [--write=json|csv] [--trim-whitespaces] [--auto-group] [--help] [file]\n";
	exit(1);
}