#!/usr/bin/perl

use strict;
use warnings;

use JSON;
use Text::CSV;
use Getopt::Long;

{
	## try to load Tie::IxHash
	my $ordered_hash_available = eval { require Tie::IxHash };
	my $xslx_format_available = eval { require Spreadsheet::XLSX };

	my $separator = undef;
	my $show_help = 0;
	my $write = "json";
	my $trim_whitespaces = 0;
	my $auto_group = 0;
	my $join_data = undef;
	my $group_with_limit = undef;
	GetOptions(
		"--separator|s=s" => \$separator,
		"--help|h!" => \$show_help,
		"--write=s" => \$write,
		"--trim-whitespaces!" => \$trim_whitespaces,
		"--auto-group!" => \$auto_group,
		"--join-data=s" => \$join_data,
		"--group-with-limit=i" => \$group_with_limit,
	) or show_help();
	show_help() if $show_help;

	## use STDIN if file name is not specified
	my ($fn) = @ARGV;
	unless (defined $fn) {
		die "input file name is required";
	}

	my ($data, $format) = smart_read_data($fn, $ordered_hash_available, $separator, $trim_whitespaces, $xslx_format_available);
	
	if (defined $group_with_limit) {
		$data = group_with_limit($data, $group_with_limit, $ordered_hash_available);
	}
	if ($auto_group) {
		$data = auto_group($data, $ordered_hash_available);
	}
	if (defined $join_data) {
		my ($join_data, undef) = smart_read_data($join_data, $ordered_hash_available, $separator, $trim_whitespaces, $xslx_format_available);
		$data = join_data($data, $join_data, $ordered_hash_available);
	}
	my $output = \*STDOUT;
	if ($write eq 'self') {
		open($output, ">", $fn) or die "can't write [$fn]: $!";
	} else {
		$format = $write;
	}
	if ($format eq 'csv') {
		write_csv($data, $separator, $output);
	} elsif ($format eq 'json') {
		write_json($data, $output);
	} elsif ($format eq 'sql') {
		write_sql($data, $fn, $output);
	} elsif ($format eq 'jira') {
		write_jira($data, $output);
	} else {
		die "can't write [$format] format";
	}
	if ($write eq 'self') {
		close($output);
	}
}

sub show_help {
	print "Usage: $0 [--separator=?] [--write=json|csv|self|jira] [--trim-whitespaces] [--auto-group] ".
		"[--join-data=file] [--group-with-limit=limit] [--help] <file>\n";
	exit(1);
}

sub smart_read_data {
    my ($fn, $ordered_hash_available, $separator, $trim_whitespaces, $xslx_format_available) = @_;
	
	my ($type_detected, $separator_detected) = smart_file_type_detection($fn, $xslx_format_available, $separator);
	unless (defined $type_detected) {
		$type_detected = 'csv';
	}
	if (defined $separator) {
		$separator_detected = $separator;
	}

	my $data = undef;
	if ($type_detected eq 'csv') {
		$data = read_csv($fn, $ordered_hash_available, $separator_detected, $trim_whitespaces);
	} elsif ($type_detected eq 'table') {
		$data = read_table($fn, $ordered_hash_available, $trim_whitespaces);
	} elsif ($type_detected eq 'xlsx') {
		$data = read_xlsx($fn, $ordered_hash_available);
	}
	unless (defined $data) {
		die "can't read $type_detected format from [$fn]";
	}
	return ($data, $type_detected);
}

sub smart_file_type_detection {
    my ($file, $xslx_format_available, $separator) = @_;
	
	## FIX doen't work with STDIN
	open(my $fh, "<", $file) or die "can't read [$file]: $!";
	my $lines = "";
	my $count = 5;
	while (<$fh>) {
		$lines .= $_;
		last unless -- $count;
	}
	close($fh);

	if ($file =~ m{\.xlsx$}) { ## *.xlsx or *.xls
		unless ($xslx_format_available) {
			die "can't parse xlsx without Spreadsheet::ParseExcel module";
		}
		return ('xlsx');
	} elsif ($lines =~ m/^\s*[{\]]/) { ## "[" or "{"
		return ('json');
	} elsif ($lines =~ m{^\s*(?:\|\s|\+-)}) { ## "| " or "+-"
		return ('table');
	} else {
		my ($first_line, $second_line, undef) = split(m{\r?\n}, $lines, 3);
		unless (defined $separator) {
			$separator = guess_separator($first_line, $second_line);
		}
		if (split($separator, $first_line) == split($separator, $second_line)) {
			return ('csv', $separator);
		}
	}
	return;
}

sub guess_separator {
    my ($first_line, $second_line) = @_;
	
	for my $separator (',', "\t", ';') {
		if (split($separator, $first_line) > 1 && split($separator, $first_line) == split($separator, $second_line)) {
			return $separator;
		}
	}
	return ',';

}

sub write_json {
	my ($data, $output) = @_;

	print $output to_json(
		$data, 
		{
			'utf8' => 1, 
			'pretty' => 1,
		}
	);
}

sub write_csv {
    my ($data, $separator, $output) = @_;
	
	my $csv = Text::CSV->new(
		{
			'binary' => 1,
			'sep_char' => ($separator // ','),
			'eol' => $/,
		} 
	) or die "can't create Text::CSV: ".Text::CSV->error_diag();

	if (@$data) {
		my @columns = keys %{ $data->[0] };
		$csv->print($output, \@columns);
		for my $row (@$data) {
			$csv->print($output, [ @$row{@columns} ]);
		}
	}
}

sub write_jira {
    my ($data, $output) = @_;
	
	if (@$data) {
		my @columns = keys %{ $data->[0] };
		print $output  "|| " . join(" || ", map { $_ // ''} @columns) . " ||\n";
		for my $row (@$data) {
			print $output "| " . join(" | ", map { $_ // ''} @$row{@columns}) . " |\n";
		}
	}
}

sub write_sql {
    my ($data, $file, $output) = @_;
	

    my $table_name = $file;
	$table_name =~ s!^.*[\\/]!!;
	$table_name =~ s!\..*$!!;
	$table_name =~ s![\W]!_!g;
	$table_name =~ s!_+!_!g;
	$table_name =~ s!^_|_$!!g;
	unless ($table_name) {
		$table_name = "unknown";
	}
	for my $row (@$data) {
		my @set;
		for my $key (keys %$row) {
			push(@set, "`$key`="._sql_quote($row->{$key}));
		}
		printf $output "INSERT INTO `%s` SET %s;\n", $table_name, join(', ', @set);
	}
}

sub _sql_quote {
    my ($str) = @_;
	
	if (defined $str) {
		if ($str =~ m{^(?:[1-9]\d*|0)$}) {
			return $str;
		} else {
			$str =~ s/\\/\\\\/g;
			$str =~ s/'/\\'/g;
			$str =~ s/\t/\\t/g;
			$str =~ s/\n/\\n/g;
			$str =~ s/\r/\\r/g;
			return "'$str'";
		}
	} else {
		return "NULL";
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

	open(my $fh, "<", $fn) or die "can't read [$fn]: $!";
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

sub read_table {
    my ($fn, $ordered_hash_available) = @_;
	
    open(my $fh, "<", $fn) or die "can't read [$fn]: $!";
    binmode($fh, ":utf8");

	my (@columns, @rows);
    my $state = 0; ## 0 - first sep, 1 - columns, 2 - second sep, 3 - data
    while (defined(my $line = <$fh>)) {
    	if ($line =~ m{^[\+-]+\s*}) { ## "+-..."
    		if ($state == 0) {
    			$state = 1;
    		} elsif ($state == 2) {
    			$state = 3;
    		} else {
    			## ignore unexpected separator
    		}
    	} else {
    		if ($state == 0 || $state == 1) {
    			@columns = get_table_columns($line);
    			$state = 2;
    		} elsif ($state == 2 || $state == 3) {
				my %r;
				if ($ordered_hash_available) {
					tie %r, "Tie::IxHash";
				}
				@r{@columns} = get_table_columns($line);
				push(@rows, \%r);
    			$state = 3;
    		}
    	}
    }
    close($fh);
	return \@rows;
}

sub read_xlsx {
    my ($fn, $ordered_hash_available) = @_;
	
	my $excel = Spreadsheet::XLSX->new($fn);
	for my $sheet (@{$excel->{'Worksheet'}}) {
		my ($columns, @rows);
        $sheet->{'MaxRow'} ||= $sheet->{'MinRow'};
        $sheet->{'MaxCol'} ||= $sheet->{'MinCol'};
        for my $row ($sheet->{'MinRow'} .. $sheet->{'MaxRow'}) {
        	if (defined $columns) {
				my %r;
				if ($ordered_hash_available) {
					tie %r, "Tie::IxHash";
				}
				@r{@$columns} = get_xlsx_columns($sheet, $row);
				delete $r{""};
				push(@rows, \%r);
        	} else {
        		$columns = [ get_xlsx_columns($sheet, $row) ];
        	}
        }
        if (@rows) {
	        return \@rows;
        }
	}
	return undef;
}

sub get_xlsx_columns {
    my ($sheet, $row) = @_;
	
	my @columns;
	for my $col ($sheet->{'MinCol'} ..  $sheet->{'MaxCol'}) {
		my $val = $sheet->{'Cells'}[$row][$col];
		push(@columns, (defined $val ? $val->{'Val'} : undef));
	}
	return @columns;
}

sub get_table_columns {
    my ($line) = @_;
	
	$line =~ s/^\s*\|\s+//;
	$line =~ s/\s+\|\s*$//;
	return split(/\s*\|\s+/, $line);
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

sub group_with_limit {
    my ($data, $limit, $ordered_hash_available) = @_;

	if (@$data) {
		my @main_columns = keys %{ $data->[0] };
		my $main_column = shift @main_columns;
		my @output;
		my %used;
		for my $row (@$data) {
			unless (exists $used{$row->{$main_column}}) {
				$used{$row->{$main_column}} = 1;
				my %r;
				if ($ordered_hash_available) {
					tie %r, "Tie::IxHash";
				}
				$r{$main_column} = $row->{$main_column};
				my $count = 0;
				for my $selected (grep {$_->{$main_column} eq $row->{$main_column}} @$data) {
					if ($count < $limit) {
						$count ++;
						for my $column (@main_columns) {
							$r{$column.' '. $count} = $selected->{$column};
						}
					} else {
						last;	
					}
				}
				while ($count < $limit) {
					$count ++;
					for my $column (@main_columns) {
						$r{$column.' '. $count} = "";
					}
				}
				push(@output, \%r);
			}
		}
		return \@output;
	} else {
		return $data;
	}
}

