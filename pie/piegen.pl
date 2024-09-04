#!/usr/bin/perl

# Generates a pie chart in WSSC source of specified radius.
# Public domain.

$radius = 0+(shift @ARGV);
die("usage: $0 radius>1\n") if ($radius < 1);

# concept:
# walk the circle for each percentage, converting the radius into x-y
# coordinates, drawing lines out and marking at which point each block
# gets set. emit the blocks as formulas.

$a360 = ((355*2)/11300); # i.e., 2*pi/100

$colbase = ord("C"); # start plots in this column
$rowbase = 1;	# start plots in the row

%matrix = ();

die("max column out of range\n") if ($colbase + $radius + $radius > ord("Z"));

# rock around the clock
$theta = 0;
for($i=1;$i<100;$i++) { # zero is obviously no cells plotted, so no line
	$theta = ((355*2*$i)/11300); # i.e., 2*pi*percent/100

	# polar to cartesian, with circle centred at (r,r) instead of (0,0)
	# and then rounded towards infinity (in this case always positive)
	$y = int((sin($theta) * $radius) + $radius + 0.5);
	$x = int((cos($theta) * $radius) + $radius + 0.5);

	# Bresenham's line draw from (r,r) to (x,y)
	$x0 = $radius;
	$y0 = $radius;
	$dx = abs($x-$x0);
	$sx = ($x0 < $x) ? 1 : -1;
	$dy = -abs($y-$y0);
	$sy = ($y0 < $y) ? 1 : -1;
	$err = $dx+$dy;

	PLOT: for(;;) {
		# "plot"
		# only mark new blocks
		$key = chr($colbase + $x0).($y0+$rowbase);
		$matrix{$key} = $i if (!$matrix{$key});

		last PLOT if ($x0 == $x && $y0 == $y);
		$e2 = $err+$err;
		if ($e2 >= $dy) {
			last PLOT if ($x0 == $x);
			$err += $dy;
			$x0 += $sx;
		}
		if ($e2 <= $dx) {
			last PLOT if ($y0 == $y);
			$err += $dx;
			$y0 += $sy;
		}
	}
}
$q = '"';
print <<'EOF';
.worksheet "Piechart"
.startcell A1
A1.5-""
A2.5-"~08~%~81~"
#                  --------------------
B1.20=If(IsNA(A1),"< Enter percentage","")
#      --------------------
B7.20-"  Chart Title Here"
EOF
foreach(sort keys %matrix) {
	print "$_.1=If(IsNA(A1),$q$q,If(A1>=$matrix{$_},$q~:~$q,$q~?~$q))\n";
}
