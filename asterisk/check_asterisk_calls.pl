#!/usr/bin/perl -w

use strict;
use warnings;
#use Data::Dumper;
use Monitoring::Plugin;
use Monitoring::Plugin::Threshold;
use Asterisk::AMI;

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

my $np = Monitoring::Plugin->new( shortname => "ASTERISK" );
$np = Monitoring::Plugin->new(usage => "Usage: %s [ -h|--help ]",);
$np->add_arg(
	spec => 'host|H=s',
	help => '-H <address>, --host=<address> AMI hostname or address',
	required => 1,
);
$np->add_arg(
	spec => 'port|P=s',
	help => '-P <number>, --port=<number> AMI port number (default: %s)',
	required => 1,
	default => "5038"
);
$np->add_arg(
	spec => 'user|u=s',
	help => '-u <username>, --user=<username> AMI username ',
	required => 1,
);
$np->add_arg(
	spec => 'secret|s=s',
	help => '-s <secret>, --secret=<secret> AMI secret',
	required => 1,
);

$np->add_arg(
	spec => 'callWarning=s',
	help => '--callWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
	spec => 'callCritical=s',
	help => '--callCritical=<THRESHOLD_DEF>',
);


$np->getopts;

my $astman = Asterisk::AMI->new(PeerAddr => $np->opts->host,
                                PeerPort => $np->opts->port,
                                Username => $np->opts->user,
                                Secret => $np->opts->secret
                                );

$np->plugin_exit( 3, "Unable to connect to asterisk") unless ($astman);

my $action = $astman->send_action({ Action => 'Command',
                                    Command => 'core show calls'
                                 });
my $response = $astman->get_response($action);

if ($response->{"GOOD"} != 1) {
	$np->plugin_exit( 3, "Error communicating with Asterisk. ". $response->{"Message"} );
}

#print $astman->amiver()."\n";



my $iCallsCurr = 0;
my $iCallsTotal = 0;

my $res = $response->{'CMD'};
for (my $i=0; $i<scalar(@$res); $i++) {
	$_ = @$res[$i];
	if (/^(\d*) active calls/) {
		($iCallsCurr) = ($_ =~ /^(\d*) active calls/);
		next;
	}
	if (/^(\d*) calls processed/) {
		($iCallsTotal) = ($_ =~ m/^(\d*) calls processed/);
		next;
	}
}

$np->add_perfdata(
	label => "active calls",
	value => $iCallsCurr,
	uom => "",
	threshold => Monitoring::Plugin::Threshold->set_thresholds(
		warning  => $np->opts->callWarning,
		critical => $np->opts->callCritical,
	),
);
$np->add_perfdata(
	label => "processed calls",
	value => $iCallsTotal,
	uom => "c",
);

my $code = 0;
my @tests;
foreach my $perf ( @{ $np->perfdata } ){
	my $lcode = $np->check_threshold(
		check => $perf->value,
		warning => $perf->threshold->warning,
		critical => $perf->threshold->critical,
	);
	if ($lcode != 0) {
		push @tests, $perf->label;
	}
	$code = max($code, $lcode);
#    print $code."-".$lcode."\n";
}
#print Dumper $np->perfdata;

my $remarks = "";
$remarks = " Also threshold checks failed for: ".join(",", @tests) if ($#tests > 0);

$np->plugin_exit( $code, "Asterisk currently handles ".$iCallsCurr." call(s). ".$remarks ) if $code != OK;
$np->plugin_exit( $code, "Asterisk currently handles ".$iCallsCurr." call(s)." );
