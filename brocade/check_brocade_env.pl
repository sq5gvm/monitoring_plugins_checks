#!/usr/bin/perl
use strict;
use Data::Dumper;
use Net::SNMP;
use Monitoring::Plugin;
use Monitoring::Plugin::Threshold;

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

my $np = Monitoring::Plugin->new( shortname => "BROCADE_ENV" );

$np = Monitoring::Plugin->new(usage => "Usage: %s [ -h|--help ]",);
$np->add_arg(
    spec => 'host|H=s',
    help => '-H <address>, --host=<address> SNMP hostname or address',
    required => 1,
);
$np->add_arg(
    spec => 'port|P=n',
    help => '-P <number>, --port=<number> SNMP port number (default: %s)',
    required => 1,
    default => 161
);
$np->add_arg(
    spec => 'community|C=s',
    help => '-C <community>, --community=<community> SNMP community',
    required => 1,
);
$np->add_arg(
    spec => 'snmpVersion=n',
    help => '--snmpVersion=<version> SNMP version (default: %s)',
    required => 1,
    default => 1
);


$np->add_arg(
    spec => 'tempWarning=s',
    help => '--tempWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
    spec => 'fanWarning=s',
    help => '--fanWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
    spec => 'pwrWarning=s',
    help => '--pwrWarning=<THRESHOLD_DEF>',
);
$np->add_arg(
    spec => 'tempCritical=s',
    help => '--tempCritical=<THRESHOLD_DEF>',
);
$np->add_arg(
    spec => 'fanCritical=s',
    help => '--fanCritical=<THRESHOLD_DEF>',
);
$np->add_arg(
    spec => 'pwrCritical=s',
    help => '--pwrCritical=<THRESHOLD_DEF>',
);



$np->getopts;

my $session;
my $error;

( $session, $error ) = Net::SNMP->session(
	-hostname  => $np->opts->host,
	-community => $np->opts->community,
	-port      => $np->opts->port,
	-version   => $np->opts->snmpVersion
);

if ( !defined($session) ) {
    $np->plugin_exit( 3, "Error communicating with device. ". $error );
}

my $confOIDroot = ".1.3.6.1.4.1.1588.2.1.1.1.1.22.1";
my $confOIDtype = ".1.3.6.1.4.1.1588.2.1.1.1.1.22.1.2";
my $confOIDdesc = ".1.3.6.1.4.1.1588.2.1.1.1.1.22.1.5";
my $confOIDval = ".1.3.6.1.4.1.1588.2.1.1.1.1.22.1.4";

my $res_status      = $session->get_table($confOIDtype);
my $res_status_data = $session->get_table($confOIDroot);
if ( defined $res_status ){
#    print Dumper $res_status_data; #->{ $snmpIfOperStatus . "." . $iface_number };

    foreach my $k (keys %{ $res_status }) {
#	print $k." -> ".$res_status->{$k}."\n";

	my @kTmpl = split("[.]", $k);
	my $i = $kTmpl[$#kTmpl];

	my $descr = $res_status_data->{$confOIDdesc.".".$i};
	$descr =~ s/^ *//; # FAN sensors in 200E (maybe in other models) is prepended with space (1)...
	my $val   = $res_status_data->{$confOIDval.".".$i};

	if ($res_status->{$k} eq 1) {
#		print "TEMP\n";
		$np->add_perfdata(
		    label => $descr,
		    value => $val,
		    uom => "",
		    threshold => Monitoring::Plugin::Threshold->set_thresholds(
			warning  => $np->opts->tempWarning,
			critical => $np->opts->tempCritical,
		    ),
		);

	} elsif ($res_status->{$k} eq 2) {
#		print "FAN\n";

		$np->add_perfdata(
		    label => $descr,
		    value => $val,
		    uom => "",
		    threshold => Monitoring::Plugin::Threshold->set_thresholds(
			warning  => $np->opts->fanWarning,
			critical => $np->opts->fanCritical,
		    ),
		);
	} elsif ($res_status->{$k} eq 3) {
#		print "PWR\n";
		$np->add_perfdata(
		    label => $descr,
		    value => $val,
		    uom => "",
		    threshold => Monitoring::Plugin::Threshold->set_thresholds(
			warning  => $np->opts->pwrWarning,
			critical => $np->opts->pwrCritical,
		    ),
		);
	}
#	print $descr." = ".$val."\n";

    }

	my $code = 0;
	my @tests;
	foreach my $perf ( @{ $np->perfdata } ){
#		print Dumper $perf->threshold;
	    my $lcode = $np->check_threshold(
		check => $perf->value,
		warning => $perf->threshold->warning,
		critical => $perf->threshold->critical,
	    );
	    if ($lcode != 0) {
		push @tests, $perf->label;
	    }
	    $code = max($code, $lcode);
	}

	my $remarks = "";
	$remarks = "Threshold checks failed for: ".join(",", @tests) if ($#tests > -1);

	$np->plugin_exit( $code, $remarks ) if $code != OK;
	$np->plugin_exit( $code, "System OK." );

} else {
        $np->plugin_exit( 3, "Error communicating with device. Unexpexted results returned." );
}
