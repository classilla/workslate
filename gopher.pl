#!/usr/bin/perl -s

# Converts Gopher menus to Workslate spreadsheets
# Use serport.c to connect to your serial device (see docs)
# example: serport /dev/ttyUSB0 9600 perl gopher
#
# Copyright (C) 2024 Cameron Kaiser. All rights reserved.
# Floodgap Free Software License.
# oldvcr.blogspot.com

eval "use bytes";
warn "starting up\n";

$fast ||= 0;
$rout = $rin = $win = $ein = '';
vec($rin, fileno(STDIN), 1) = 1;
select(STDOUT); $|++;
select(STDIN); $|++;

$AF_INET = 2;
$SOCK_STREAM = 1;
($x,$x,$IPPROTO_TCP) = getprotobyname("tcp");
$sockaddr = 'S n a4 x8';

# not every system might have Socket.pm
if (eval("use Socket; 99") == 99) {
	# not every Socket.pm might define these
	eval '$AF_INET = AF_INET if (0+&AF_INET)';
	eval '$SOCK_STREAM = SOCK_STREAM if (0+&SOCK_STREAM)';
	eval '$IPPROTO_TCP = IPPROTO_TCP if (0+&IPPROTO_TCP)';
}

$bs = chr(8);
$lf = chr(10);
$cr = chr(13);
$crlf = "$cr$lf"; # ~-*~ to the Workslate
$n = 0;
$t = 0;

$init = pack("H*", "121211");
$term = pack("H*", "0311");

%menu = ();
$defhost = $ARGV[0] || 'gopher.floodgap.com';
$defport = $ARGV[1] || 70;
$defsel = $ARGV[2] || '/';
$defitype = $ARGV[3] || '1';
$menu{'001'}=[ $defhost, $defport, $defitype, $defsel ];
@state = ();
$global_error = 0;

# initial log on
# everything is unbuffered so we can use select to wait on filehandles
for(;;) {
	warn "waiting for Terminal\n";
	for(;;) {
		($n, $t) = select($rout = $rin, undef, undef, undef);
		last if ($n);
	}
	# "flush"
	sysread(STDIN, $buf, 99);
	$buf = unpack("H*", $buf);
	if ($buf !~ /05/) {
		warn "got '$buf', didn't see ENQ\n";
		next;
	}
	last;
}
warn "got ENQ from Terminal, waiting for user\n";

for(;;) {
	# wait for activity
	syswrite(STDOUT, "${lf}");
	sleep 2 unless ($fast);
#                                ----------------------------------------------
	syswrite(STDOUT, "${crlf}Press Do It to start.");
	for(;;) {
		($n, $t) = select($rout = $rin, undef, undef, 2);
		last if ($n);
		# in case user accidentally hung up, they can get back in
		# without restarting
		syswrite(STDOUT, "${lf}");
	}
	# "flush"
	sysread(STDIN, $buf, 99);
	last; # XXX?
}
warn "sending default menu\n";

# send init to prompt Workslate for download slot
#                        ----------------------------------------------
syswrite(STDOUT, "${crlf}Transmitting initial menu in 5 seconds.${crlf}${init}");
sleep 5 unless ($fast);

syswrite(STDOUT,
	'\S B1 A1 A1  A E c ' . $crlf .
	# base is 144 bytes
	# for an active two-column row, add 33 plus the length of the string
	# for each additional column, add 4 plus the length of each string
	# i.e., 37, 41, 45 ... (i.e., 29 + 4 * number of text columns)
	# we don't support lines more than five columns (that's 159 chars)

	# for a non-selectable row with a null first column (nothing in A):
	# two-column, add 6 plus the length of the string
	# for each additional column, add 4 plus the length of each string
	# i.e., 10, 14, 18 ... (i.e., 2 + 4 * number of text columns)
	'\M 229' . $crlf .			# this count is correct
	'\N " Gopher "' . $crlf .
	'\W 1 39 ' . $crlf .

	'A1=Send("001~-*~")+WaitFor("*")' . $crlf .
	'B1-"Floodgap Gopher"' . $crlf .

	'A2=Send("000~-*~")+WaitFor("*")' . $crlf .
	'B2-"Quit"' . $crlf .
$term);
warn "main menu served, entering control loop\n";

$buf = '';
INLOOP: for(;;) {
	$global_error = 0; alarm 0;

	# terminal connection loop - send LFs every second until
	# we get something on standard input in case user accidentally
	# hung up
	LF: for(;;) {
		($n, $t) = select($rout = $rin, undef, undef, 1);
		if ($t == 1 && $n == 0) {
			# probably interrupted by a signal or syscall
			syswrite(STDOUT, $lf) unless ($fast);
			next LF;
		}
		if ($t == $n && $t == 0) {
			syswrite(STDOUT, $lf) unless ($fast);
			next LF;
		}
		last LF;
	}
	$t = '';
	$n = sysread(STDIN, $t, 10);
	# edit out control characters, there may be ones left over
	$t = join("", grep { ord($_) > 31 } split("", $t));
	$buf .= $t;
	next if (length($buf) < 3);

	# received a command, I think
	warn "command received: '" . unpack("H*", $buf) . "' => $buf\n";
	$cbuf = $buf; $buf = '';

	if ($cbuf eq '000') {
		warn "quit requested, exiting\n";
		syswrite(STDOUT, "*${bs}${crlf}Goodbye.${crlf}");
		sleep 2 unless ($fast);
		exit 0;
	}
	next if ($global_error);

	# navigation
	if ($cbuf eq '999') {
		warn "back requested\n";
		next if (!scalar(@state));
		($host, $port, $itype, $sel) = @{ pop(@state) };
	} else {
		next if (!defined($menu{$cbuf})); # or maybe not?
		push(@state, [ $host, $port, $itype, $sel ])
			if (length($host));
		($host, $port, $itype, $sel) = @{ $menu{$cbuf} };
		# this shouldn't ever happen
		die("assert: bad item type $itype")
			if ($itype ne '0' && $itype ne '1');
	}
	warn "accessing $host:$port (itype $itype, sel \"$sel\")\n";

	# phase one: resolve hostname
	$SIG{'ALRM'} = sub {
		&error($itype, "Timeout resolving host");
	};
	alarm 10;
	($name, $aliases, $type, $len, $thataddr) = gethostbyname($host);
	&error($itype, "Can't resolve host $host.") if (!$name);
	&error($itype, "Only IPv4 supported.") if ($len >0 && $len != 4);
	next if ($global_error);

	# phase two: connect
	$SIG{'ALRM'} = sub {
		&error($itype, "Timeout connecting to host.");
	};
	alarm 10;
	$that = pack($sockaddr, 2, $port, $thataddr, 0);
	socket(S, $AF_INET, $SOCK_STREAM, $IPPROTO_TCP) || &error("socket: $!");
	&error($itype, "connect: $!") unless (connect(S, $that));
	next if ($global_error);

	# phase 3: send selector
	select(S); $|++;
	print S "$sel$crlf";

	# phase 4: prepare contents and convert to Workslate cells
	# do line by line
	$SIG{'ALRM'} = sub {
		&error($itype, "Timeout receiving data.");
	};
	# always include quit option, but put back first for convenience
	# (shift-up)
	@buffer = ();
	push(@buffer, [ 999, [ 4, "Back" ] ]) if (scalar(@state));
	push(@buffer, [  0,  [ 4, "Quit" ] ]);
	push(@buffer, [ -1,  [ 1,   " "  ] ]);
	%menu = (); alarm 10; $unn = 0; $cols = 1; while(<S>) {
		next INLOOP if ($global_error);
		chomp; chomp; alarm 10;

# concept: read each line
# links get a spreadsheet cell to send that number, then store that
# number in the menu map so the Workslate doesn't need to remember it
# split long lines into multiple cells (1, 39, 40, 40 ...)
# track widest point and longest line for the spreadsheet header
# stop when oversized

		next if (scalar(@buffer) == 128); # oversize
		if (scalar(@buffer) == 127) {
			push(@buffer, [ -2, [ 13, "[Out of rows]" ]]);
			next;
		}

		if ($itype eq '0') {
			# non-selectable row
			push(@buffer, [ -1, &splitstr($_) ]);
			next;
		}

		if (!/\t/) {
			# probably a spurious blank or oversight
			# make a non-selectable row
			push(@buffer, [ -1, &splitstr($_) ]);
			next;
		}

		($ids, $nsel, $nhost, $nport, $gplus) = split(/\t/, $_, 5);
		$ds = substr($ids, 1); $ds = " " if (!length($ds));
		if (/^[^i01]/) {
			# itype we don't support, including hURLs, etc.
			# make a non-selectable row with an unsupported mark
			push(@buffer, [ -2, &splitstr($ds) ]);
			next;
		}
		if (substr($ids, 0, 1) eq 'i') {
			# info line, make non-selectable
			push(@buffer, [ -1, &splitstr($ds) ]);
			next;
		}
		$nport += 0;
		if (!length($nhost) || $nport < 1 || $nport > 65535) {
			# bogus or malformed, make unsupported mark
			push(@buffer, [ -2, &splitstr($ds) ]);
			next;
		}
		push(@buffer, [ ++$unn, &splitstr($ds) ]);
		$menu{sprintf("%03d", $unn)} = [ $nhost, $nport,
			substr($ids, 0, 1), $nsel ];
	}
	alarm 0;
	next if ($global_error); # paranoia

	# phase 5: notify user
	syswrite(STDOUT, "*${bs}${crlf}Next menu is ready.${crlf}");
#                 ----------------------------------------------
syswrite(STDOUT, "Transmitting in five seconds.${crlf}${init}");
	close(S);

	sleep 5 unless ($fast);
	# compute estimated memory size and copy to safe buffer
	@nubuf = ();
	$msize = 144; foreach(@buffer) {
		my $n;
		my $s;
		my @q;	

		($n, $s) = @{ $_ }; @q = @{ $s };

		$msize += (($n == -1) ? 2 : ($n == -2) ? 5 : 29);
		$msize += 4 * $cols;
		$msize += shift(@q);
		push(@nubuf, [ $n, \@q ]);
		if ($msize > 12600) { # worst case with a fudge; max is 12868
			push(@nubuf, [ -2, [ 15, "[Out of memory]" ]])
				if (scalar(@nubuf) < 128);
			last;
		}
	}
	warn "transmitting sheet (@{[ scalar(@nubuf) ]} rows, $msize bytes)\n";
	syswrite(STDOUT,
		'\S ' . chr(65 + $cols) . scalar(@nubuf) .
			' A1 A1  A E c ' . $crlf .
		'\M ' . $msize . $crlf .
		'\N " Gopher "' . $crlf .
		'\W 1 39 ' .
			(($cols > 1) ? "40+".($cols-1) : '') . $crlf);
	$row = 0;
	foreach(@nubuf) {
		my $n;
		my $s;
		my @q;
		my $c = 65; # 'A'

		($n, $s) = @{ $_ }; @q = @{ $s }; $row++;

		# column A
		if ($n == -2) {
			# print x
			syswrite(STDOUT, "A$row" . '-"~$~"' . $crlf);
		} elsif ($n == -1) {
			# nothin'
		} else {
			# selectable row, emit formula
			syswrite(STDOUT, "A$row" . '=Send("' .
				sprintf("%03d", $n) .
				'~-*~")+WaitFor("*")' . $crlf);
		}

		# remaining columns starting with B
		foreach(@q) {
			syswrite(STDOUT, chr(++$c) . $row .
				'-"' . $_ . '"' .  $crlf);
		}
	}
	syswrite(STDOUT, $term);
	warn "transmission complete, resuming control loop\n";
}

sub error {
	my $type = shift @_; # XXX

	$global_error = 1;
	return if ($type ne '0' && $type ne '1' && $type ne '7'); # XXX
	# make sure to cancel the WaitFor
	syswrite(STDOUT, "*${bs}@_${crlf}");
}

sub splitstr {
	# split a string into 39, 40, 40, 40 character pieces
	# trim after 159

	my $s = shift @_;
	my @q = ();

	# remove control characters and 8-bit characters
	$s = join('', grep { (ord($_) > 31) && (ord($_) < 128) }
		split('', $s));

	# trim to length
	$s = substr($s, 0, 159); $s = ' ' if (!length($s));

	# chop up
	push(@q, substr($s,   0, 39));
	push(@q, substr($s,  39, 40)) if (length($s) > 39);
	push(@q, substr($s,  79, 40)) if (length($s) > 79);
	push(@q, substr($s, 119, 40)) if (length($s) > 119);

	# set global column width
	$cols = (scalar(@q) > $cols) ? scalar(@q) : $cols;

	# escape tildes
	map { tr/~/~~/ } @q;
	unshift(@q, length($s));

	# wunnerful, wunnerful
	return \@q;
}
