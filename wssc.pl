#!/usr/bin/perl -s

# Workslate Spreadsheet Crossassembler
# Copyright (C) 2024 Cameron Kaiser. All rights reserved.
# Floodgap Free Software License
# oldvcr.blogspot.com

# options
$fwidth ||= 13;
$dwidth ||= 9;
$include_mem ||= 0;
$wbig_file ||= 0;
$wno_warn_width ||= 0;
$wwarn_default_width ||= 0;
$sheet ||= " empty  ";

# state
@widths = ();
%cells = ();
$maxcol = "";
$maxrow = 0;
$mem = 144;

# constants
$orda = ord('A');
$maxmem = 12868; # brute force testing
$crlf = pack("H*", "0d0a");

$line = 0;
while(<>) {
	$line++; chomp; chomp; s/^\s+//; s/\s+$//; next if (!length || /^#/);

	if (/^\.([a-z0-9]+)\s(.+)$/) { # pseudo-ops
		$psop = $1;
		$arg = $2;

		if ($psop eq 'worksheet') {
			&error("worksheet name must be eight chars with quotes")
				if (length($arg) != 10 ||
					$arg !~ /^\".+\"$/);
			$sheet = substr($arg, 1, 8);
			next;
		} elsif ($psop eq 'startcell') {
			if ($arg =~ /^([A-Za-z]+)([0-9]+)$/) {
				$cnl = uc($1);
				$row = &rowtonum($2);
				$col = &coltonum($cnl);
				$startcell = $arg;
			} else {
				&error("startcell needs a cell reference");
			}
			next;
		} elsif ($psop eq 'fwidth') {
			$fwidth = 0+$arg;
			next;
		} elsif ($psop eq 'dwidth') {
			$dwidth = 0+$arg;
			next;
		} else {
			&error("unknown pseudo-op $psop\n");
		}
	} elsif (/^([A-Za-z]+)([0-9]+)\.([0-9]+)([-=])(.+)$/) {
		$cnl = uc($1);
		$col = &coltonum($cnl);
		$row = &rowtonum($2);
		$width = 0+$3;
		&error("illegal cell width $width")
			if ($width < 1 || $width > 40);
		&error("column $cnl already defined with width $widths[$col]")
			if ($widths[$col] > 0 && $widths[$col] != $width);
		&oops("column $cnl was used previously with default width")
			if (defined($widths[$col]) && $widths[$col] == 0 && !$wno_warn_width);
		$widths[$col] = $width;
		$forc = $4;
		$arg = $5;
	} elsif (/^([A-Za-z]+)([0-9]+)([-=])(.+)$/) {
		$cnl = uc($1);
		$col = &coltonum($cnl);
		$row = &rowtonum($2);
		if ($widths[$col] > 0) {
			&oops("column $cnl has non-default width of $widths[$col]")
				if ($wwarn_default_width);
		} else {
			$widths[$col] = 0;
		}
		$forc = $3;
		$arg = $4;
	} else {
		&error("malformed line error");
	}

	&error("cell $cnl$row already defined")
		if (defined($cells{"$cnl$row"}));

	# remove trailing format character temporarily
	$trailer = '';
	if ($arg =~ s/\s+([DWLRO]|[LRO] [DW])$//) {
		$trailer = " $1";
	}

	if ($forc eq '-') { # constant
		if ($arg =~ /^"/) { # string
			# count tildes, they must be balanced
			$tcount = ($arg =~ tr/~//);
			&error("tilde escapes must be balanced")
				if ($tcount & 1);
			
			# quotes can appear inside the string, so all we can
			# do is ensure there is one at the beginning and end
			if ($arg !~ /"$/) {
				&oops("missing closing string quote");
				$arg .= '"';
			}

			# compute length with tilde escapes converted
			$mem += &tilength($arg);
		} else { # number
			# treat as strings so Perl doesn't coerce them
			if ($arg =~ /^([-+]?)([0-9]+)$/) { # integer
				$sign = $1;
				$int = $2;

				$int =~ s/^0+//;
				$int = "0" if (!length($int));
				$arg = (($sign eq '-') ? '-' : '') . $int;
			} elsif ($arg =~ /^([-+]?)([0-9]*)\.([0-9]*)$/) {
				$sign = $1;
				$int = $2;
				$frac = $3;
				&oops("missing integer portion of float")
					 if (!length($int));
				&oops("missing fractional portion of float")
					 if (!length($frac));

				$int =~ s/^0+//;
				$int = "0" if (!length($int));
				$frac =~ s/0+$//;
				$arg = (($sign eq '-') ? '-' : '') . $int .
					((length($frac)) ? ".$frac" : '');
			} else {
				&error("could not parse number constant");
			}
			&tilength($arg); # paranoia
			$mem += 8;
		}
	} else { # formula

		# conversions for convenience?

		# XXX: this is wrong. numbers are at least 7 bytes regardless
		# of length, and primitive functions are tokenized to be
		# smaller than their length. however, this is a good rule of
		# thumb and prevents me having to write an entire parser just
		# to figure out the accurate length until I have to. the
		# Workslate only uses the \M field to determine if the sheet
		# will fit in memory before it tries to load it, so this does
		# not need to be exact right now.
		$w = &tilength($arg);
		&error("formula too complex (length $w)") if ($w > 108);
		$mem += $w;
		# add four bytes for each number
		$mem += 4*($arg =~ tr/0-9//);
	}

	&error("estimated size $mem bytes greater than RAM") if (!$wbig_file && ($mem > $maxmem));
	$cells{"$cnl$row"} = $forc . $arg . $trailer;
	$maxcol = $cnl if (!length($maxcol) || $col > &coltonum($maxcol));
	$maxrow = $row if ($row > $maxrow);
}
&error("no valid cells entered\n") if (!length($maxcol) || !$maxrow);
$imaxcol = &coltonum($maxcol);

$mem += 2*($maxrow*$imaxcol);
&error("estimated size $mem bytes greater than RAM") if (!$wbig_file && ($mem > $maxmem));

&oops("no cell A1") if (!defined($cells{"A1"}));

$line = -1;
&error("sheet name should be exactly eight characters")
	if (length($sheet) != 8);
&error("default cell widths must be 1-40")
	if ($fwidth > 40 || $dwidth > 40 || $fwidth < 1 || $dwidth < 1);

$widthstr = "\\W ";
$last = ($widths[1]) ? $widths[1] : $fwidth;
$lastcount = 1;
if ($imaxcol > 1) {
	for($i=2;$i<=$imaxcol;$i++) {
		$nwidth = ($widths[$i]) ? $widths[$i] : $dwidth;
		if ($nwidth != $last) {
			$widthstr .= $last;
			$widthstr .= "+$lastcount" if ($lastcount > 1);
			$widthstr .= " ";
			$last = ($widths[$i]) ? $widths[$i] : $dwidth;
			$lastcount = 1;
		} else {
			$lastcount++;
		}
	}
}
$widthstr .= $last;
$widthstr .= "+$lastcount" if ($lastcount > 1);
$widthstr .= " ";

# emit
select(STDOUT); $|++; binmode(STDOUT);
print pack("H*", "121211");
$startcell ||= "$maxcol$maxrow";
print "\\S $maxcol$maxrow A1 $startcell  A E c $crlf";
print (($wbig_file) ? "\\M 0$crlf" : 
		($include_mem) ? "\\M $mem$crlf" : "\\M 1$crlf");
print "\\N \"$sheet\"$crlf";
print "$widthstr$crlf";
foreach (sort { &celtonum($a) <=> &celtonum($b) } keys %cells) {
	print "$_$cells{$_}$crlf";
}
print pack("H*", "0311");
exit;

sub oops { warn("note: at line $line, ".shift."\n"); }
sub error { die("error: at line $line, ".shift."\n"); }

# convert a column name to a number
sub coltonum {
	my $c = uc(shift);
	&error("syntax error in column name $c") if (0 ||
		length($c) > 2 ||
		$c =~ /[^A-Z]/ ||
	0);
	my $num = ord(substr($c, -1, 1)) + 1 - $orda;
	$num += 26*(ord(substr($c, 0, 1)) + 1 - $orda)
		if (length($c) > 1);
	&error("illegal quantity error in column name $c")
		if ($num < 1 || $num > 128);
	return $num;
}

sub rowtonum {
	my $c = 0+shift;
	&error("illegal quantity error in row number $c")
		if ($c < 1 || $c > 128);
	return $c;
}

sub celtonum {
	my $c = shift;

	if ($c =~ /^([A-Z]+)([0-9]+)$/) {
		return (&rowtonum($2) * 128 + &coltonum($1));
	}
	&error("nonsense cell reference $c");
}

sub tilength {
	my $c = shift;
	my $j;

	1 while $c =~ s/\~([^~]+)\~/\1/;
	$j = length($c);
	&error("line too long (computed $j characters)") if ($j > 126);
	return $j;
}
